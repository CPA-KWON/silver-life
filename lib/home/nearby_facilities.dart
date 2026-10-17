import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_theme.dart';
import '../facility/local_facility_search.dart';
import '../facility/naver_local_search.dart';
import '../ui/design_widgets.dart';

enum NearbyFailure {
  permissionDenied,
  permissionDeniedForever,
  locationUnavailable,
  rateLimited,
  searchFailed,
}

class NearbyException implements Exception {
  const NearbyException(this.failure);
  final NearbyFailure failure;

  @override
  String toString() => 'NearbyException($failure)';
}

class NearbyFacility {
  const NearbyFacility({required this.result, required this.typeLabel});
  final FacilityResult result;

  /// The category we searched ('경로당' | '병원' | '약국').
  final String typeLabel;
}

typedef NearbyLoader = Future<List<NearbyFacility>> Function({bool force});

class NearbyFacilitiesService {
  NearbyFacilitiesService._();
  static final NearbyFacilitiesService instance = NearbyFacilitiesService._();

  static const _ttl = Duration(minutes: 10);
  // Past [_ttl] the position is re-read; if the user hasn't moved far, the
  // cached list is still reused up to this age before searching again.
  static const _maxReuse = Duration(minutes: 30);
  static const _moveThresholdMeters = 500.0;

  Position? _cachedPosition;
  DateTime? _fetchedAt;
  List<NearbyFacility>? _cached;

  Future<List<NearbyFacility>> load({bool force = false}) async {
    // A fresh cache is returned as-is, without even reading the position,
    // so revisiting the home tab costs no GPS read and no search calls.
    final freshAt = _fetchedAt;
    if (!force &&
        _cached != null &&
        freshAt != null &&
        DateTime.now().difference(freshAt) < _ttl) {
      return _cached!;
    }

    final permission = await _ensurePermission();
    if (permission == LocationPermission.denied) {
      throw const NearbyException(NearbyFailure.permissionDenied);
    }
    if (permission == LocationPermission.deniedForever) {
      throw const NearbyException(NearbyFailure.permissionDeniedForever);
    }

    final position = await _readPosition();

    final cached = _cached;
    final cachedPos = _cachedPosition;
    final at = _fetchedAt;
    if (!force &&
        cached != null &&
        cachedPos != null &&
        at != null &&
        DateTime.now().difference(at) < _maxReuse &&
        Geolocator.distanceBetween(
              cachedPos.latitude,
              cachedPos.longitude,
              position.latitude,
              position.longitude,
            ) <=
            _moveThresholdMeters) {
      return cached;
    }

    final lat = position.latitude;
    final lng = position.longitude;
    var rateLimited = false;

    // Track whether every call failed (vs. succeeded with no results).
    var failures = 0;
    Future<List<NearbyFacility>> guarded(
      String label,
      Future<List<FacilityResult>> Function() search,
    ) async {
      try {
        final list = await search();
        return [
          for (final r in list) NearbyFacility(result: r, typeLabel: label),
        ];
      } on FacilityRateLimitException {
        rateLimited = true;
        failures++;
        return const [];
      } catch (_) {
        failures++;
        return const [];
      }
    }

    final parts = await Future.wait([
      guarded(
        '경로당',
        () => searchOwnFacilities(category: '경로당', lat: lat, lng: lng),
      ),
      guarded(
        '병원',
        () => searchNearbyFacilities(category: '병원', lat: lat, lng: lng),
      ),
      guarded(
        '약국',
        () => searchNearbyFacilities(category: '약국', lat: lat, lng: lng),
      ),
    ]);
    final merged = [for (final p in parts) ...p]
      ..sort(
        (a, b) => a.result.distanceMeters.compareTo(b.result.distanceMeters),
      );
    final top = merged.take(3).toList();

    if (failures > 0 && merged.isEmpty) {
      throw NearbyException(
        rateLimited ? NearbyFailure.rateLimited : NearbyFailure.searchFailed,
      );
    }
    // Do not cache partial results so a retry can fill in the gaps.
    if (failures == 0) {
      _cached = top;
      _cachedPosition = position;
      _fetchedAt = DateTime.now();
    }
    return top;
  }

  Future<LocationPermission> _ensurePermission() async {
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }
      return p;
    } catch (_) {
      throw const NearbyException(NearbyFailure.locationUnavailable);
    }
  }

  Future<Position> _readPosition() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp).abs() <=
              const Duration(minutes: 5)) {
        return last;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      throw const NearbyException(NearbyFailure.locationUnavailable);
    }
  }

  /// Requests permission only (used by the "권한 허용" button).
  Future<void> requestPermission() async {
    try {
      await Geolocator.requestPermission();
    } catch (_) {}
  }
}

String formatNearbyDistance(double meters) {
  if (meters < 1000) return '${meters.round()}m';
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

class NearbyFacilitiesSection extends StatefulWidget {
  const NearbyFacilitiesSection({
    super.key,
    required this.onOpenFacility,
    required this.onShowMap,
    this.loader,
    this.refreshVersion = 0,
  });

  final void Function(FacilityResult) onOpenFacility;
  final VoidCallback onShowMap;

  /// Test hook: replaces the real service.
  final NearbyLoader? loader;
  final int refreshVersion;

  @override
  State<NearbyFacilitiesSection> createState() =>
      _NearbyFacilitiesSectionState();
}

class _NearbyFacilitiesSectionState extends State<NearbyFacilitiesSection> {
  bool _loading = true;
  NearbyFailure? _failure;
  List<NearbyFacility> _items = const [];
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant NearbyFacilitiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final list = await (widget.loader != null
          ? widget.loader!(force: force)
          : NearbyFacilitiesService.instance.load(force: force));
      if (!mounted || token != _token) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } on NearbyException catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _failure = e.failure;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _failure = NearbyFailure.searchFailed;
        _loading = false;
      });
    }
  }

  Future<void> _grantPermission() async {
    await NearbyFacilitiesService.instance.requestPermission();
    if (mounted) await _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      header: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text('내 주변 시설', style: theme.textTheme.titleMedium),
            ),
            TextButton(
              onPressed: widget.onShowMap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                minimumSize: const Size(48, 56),
              ),
              child: const Text('지도에서 보기'),
            ),
          ],
        ),
      ),
      child: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: 120),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      );
    }
    final failure = _failure;
    if (failure != null) return _buildFailure(context, failure);
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '주변에서 찾은 시설이 없어요',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in _items)
          _NearbyRow(
            item: item,
            onTap: () => widget.onOpenFacility(item.result),
          ),
      ],
    );
  }

  Widget _buildFailure(BuildContext context, NearbyFailure failure) {
    final (message, label, action) = switch (failure) {
      NearbyFailure.permissionDenied => (
        '위치 권한을 허용하면 주변 시설을 볼 수 있어요',
        '권한 허용',
        _grantPermission,
      ),
      NearbyFailure.permissionDeniedForever => (
        '위치 권한을 허용하면 주변 시설을 볼 수 있어요',
        '설정 열기',
        () => Geolocator.openAppSettings(),
      ),
      NearbyFailure.locationUnavailable => (
        '현재 위치를 확인할 수 없어요',
        '다시 시도',
        () => _load(force: true),
      ),
      NearbyFailure.rateLimited => (
        '잠시 후 다시 시도해 주세요',
        '다시 시도',
        () => _load(force: true),
      ),
      NearbyFailure.searchFailed => (
        '주변 시설을 불러오지 못했어요',
        '다시 시도',
        () => _load(force: true),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () => action(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: AppColors.primary,
              backgroundColor: AppColors.tint,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow({required this.item, required this.onTap});

  final NearbyFacility item;
  final VoidCallback onTap;

  TagTone get _tone => switch (item.typeLabel) {
    '병원' => TagTone.blue,
    '약국' => TagTone.mint,
    _ => TagTone.lavender,
  };

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48),
                child: Center(
                  child: TagBadge(label: item.typeLabel, tone: _tone),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.result.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatNearbyDistance(item.result.distanceMeters),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'naver_local_search.dart';

const kFacilityCategories = ['병원', '약국', '경로당', '복지관'];
const kHospitalSubcategories = ['내과', '정형외과', '안과', '치과', '이비인후과', '피부과'];

class FacilitySearchPage extends StatefulWidget {
  const FacilitySearchPage({super.key});

  @override
  State<FacilitySearchPage> createState() => _FacilitySearchPageState();
}

class _FacilitySearchPageState extends State<FacilitySearchPage> {
  static const _seoulCityHall = NLatLng(37.5666, 126.979);

  NaverMapController? _controller;
  String? _category;
  String? _subcategory;
  bool _isSearching = false;

  Future<Position> _currentPosition() async {
    final status = await Permission.location.request();
    if (!status.isGranted) {
      throw Exception('위치 권한이 필요합니다.');
    }
    return Geolocator.getCurrentPosition();
  }

  void _selectCategory(String category) {
    // Picking a top-level category (e.g. re-tapping "병원") resets any
    // hospital specialty filter and searches the broad category again.
    setState(() {
      _category = category;
      _subcategory = null;
    });
    _search(category);
  }

  void _selectSubcategory(String subcategory) {
    setState(() => _subcategory = subcategory);
    _search(subcategory);
  }

  Future<void> _search(String searchTerm) async {
    final controller = _controller;
    if (controller == null || _isSearching) return;

    setState(() => _isSearching = true);

    try {
      final position = await _currentPosition();
      final results = await searchNearbyFacilities(
        category: searchTerm,
        lat: position.latitude,
        lng: position.longitude,
      );

      await controller.clearOverlays(type: NOverlayType.marker);
      for (final result in results) {
        final marker = NMarker(
          id: '${result.lat},${result.lng},${result.name}',
          position: NLatLng(result.lat, result.lng),
          caption: NOverlayCaption(text: result.name),
        );
        marker.setOnTapListener((_) => _showFacilitySheet(result));
        await controller.addOverlay(marker);
      }

      if (results.isNotEmpty && mounted) {
        await controller.updateCamera(
          NCameraUpdate.withParams(
            target: NLatLng(results.first.lat, results.first.lng),
            zoom: 15,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('주변에서 "$searchTerm"를 찾지 못했습니다.')));
      }
    } on FacilityRateLimitException {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('오늘은 검색이 많아 잠시 후 다시 시도해주세요.')),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('검색에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _showFacilitySheet(FacilityResult result) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(result.address, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 4),
              Text(
                '약 ${(result.distanceMeters / 1000).toStringAsFixed(1)}km',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (result.telephone.isNotEmpty) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse('tel:${result.telephone}')),
                  icon: const Icon(Icons.call),
                  label: Text('${result.telephone} 전화 걸기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NaverMap(
          options: const NaverMapViewOptions(
            initialCameraPosition: NCameraPosition(
              target: _seoulCityHall,
              zoom: 14,
            ),
            locationButtonEnable: true,
          ),
          onMapReady: (controller) async {
            _controller = controller;
            final status = await Permission.location.request();
            if (status.isGranted) {
              controller.setLocationTrackingMode(NLocationTrackingMode.follow);
            }
          },
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CategoryBar(
                selected: _category,
                isSearching: _isSearching,
                onSelected: _selectCategory,
              ),
              if (_category == '병원') ...[
                const SizedBox(height: 8),
                _CategoryBar(
                  categories: kHospitalSubcategories,
                  selected: _subcategory,
                  isSearching: _isSearching,
                  onSelected: _selectSubcategory,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    this.categories = kFacilityCategories,
    required this.selected,
    required this.isSearching,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selected;
  final bool isSearching;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            for (final category in categories)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(category),
                  selected: selected == category,
                  onSelected: isSearching ? null : (_) => onSelected(category),
                ),
              ),
            if (isSearching)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

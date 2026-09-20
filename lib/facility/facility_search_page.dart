import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../community/post_detail_page.dart';
import '../core/address_region.dart';
import 'local_facility_search.dart';
import 'naver_local_search.dart';

const kFacilityCategories = ['병원', '약국', '경로당', '복지관'];
const kHospitalSubcategories = ['내과', '정형외과', '안과', '치과', '이비인후과', '피부과'];

class FacilitySearchPage extends StatefulWidget {
  const FacilitySearchPage({super.key, this.onPicked, this.initialFacility});

  /// When set, tapping a marker calls this with the picked facility instead
  /// of opening the detail sheet — used by the "장소 선택" flow for meetup
  /// posts (see [FacilityPickerPage]).
  final ValueChanged<FacilityResult>? onPicked;

  /// When set, the detail overlay opens immediately showing this facility —
  /// used when arriving here from outside the map (e.g. tapping a favorite
  /// on the home tab) instead of by tapping a marker.
  final FacilityResult? initialFacility;

  @override
  State<FacilitySearchPage> createState() => _FacilitySearchPageState();
}

class _FacilitySearchPageState extends State<FacilitySearchPage> {
  static const _seoulCityHall = NLatLng(37.5666, 126.979);

  NaverMapController? _controller;
  String? _category;
  String? _subcategory;
  bool _isSearching = false;
  // Shown after the user manually pans/zooms the map (not after our own
  // post-search recenter), so they can re-search around wherever they
  // scrolled to instead of always their GPS location.
  bool _showSearchHereButton = false;
  // Shown as an in-place overlay (not a pushed route) so the NaverMap
  // PlatformView underneath is never touched by a Navigator transition —
  // see _openFacilityDetail for why.
  late FacilityResult? _selectedFacility = widget.initialFacility;

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
    _searchNearMe(category);
  }

  void _selectSubcategory(String subcategory) {
    setState(() => _subcategory = subcategory);
    _searchNearMe(subcategory);
  }

  Future<void> _searchNearMe(String searchTerm) async {
    final position = await _currentPosition();
    await _search(searchTerm, position.latitude, position.longitude);
  }

  Future<void> _searchHere() async {
    final controller = _controller;
    final searchTerm = _subcategory ?? _category;
    if (controller == null || searchTerm == null) return;
    final position = await controller.getCameraPosition();
    await _search(
      searchTerm,
      position.target.latitude,
      position.target.longitude,
    );
  }

  Future<void> _search(String searchTerm, double lat, double lng) async {
    final controller = _controller;
    if (controller == null || _isSearching) return;

    setState(() {
      _isSearching = true;
      _showSearchHereButton = false;
    });

    try {
      final results = kLocallySourcedCategories.contains(searchTerm)
          ? await searchOwnFacilities(category: searchTerm, lat: lat, lng: lng)
          : await searchNearbyFacilities(
              category: searchTerm,
              lat: lat,
              lng: lng,
            );

      await controller.clearOverlays(type: NOverlayType.marker);
      for (final result in results) {
        final marker = NMarker(
          id: '${result.lat},${result.lng},${result.name}',
          position: NLatLng(result.lat, result.lng),
          caption: NOverlayCaption(text: result.name),
        );
        marker.setOnTapListener(
          (_) => widget.onPicked != null
              ? widget.onPicked!(result)
              : _openFacilityDetail(result),
        );
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
          ..showSnackBar(
            SnackBar(content: Text('주변에서 "$searchTerm"를 찾지 못했습니다.')),
          );
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

  // Shown as an in-place overlay instead of a pushed route. Even a
  // zero-duration PageRouteBuilder still made the Navigator mount a second
  // route on top of this one for a frame, and native PlatformViews (Hybrid
  // Composition) handle that kind of transient compositing very poorly —
  // it kept corrupting the render tree ("RenderBox was not laid out"
  // cascades, "BoxConstraints forces an infinite width", sometimes hanging
  // entirely). Keeping the NaverMap's page permanently mounted with no
  // route ever pushed around it removes the conflict at the source.
  void _openFacilityDetail(FacilityResult result) {
    setState(() => _selectedFacility = result);
  }

  void _closeFacilityDetail() {
    setState(() => _selectedFacility = null);
  }

  @override
  Widget build(BuildContext context) {
    // Intercepts the hardware/gesture back button while the detail overlay
    // is open so it closes the overlay instead of popping this whole page
    // (there is no separate route to pop back out of any more).
    return PopScope(
      canPop: _selectedFacility == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedFacility != null) _closeFacilityDetail();
      },
      child: Stack(
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
          onCameraChange: (reason, animated) {
            final userMoved =
                reason == NCameraUpdateReason.gesture ||
                reason == NCameraUpdateReason.control;
            if (userMoved &&
                (_subcategory ?? _category) != null &&
                !_showSearchHereButton) {
              setState(() => _showSearchHereButton = true);
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
              if (widget.onPicked != null) ...[
                const SizedBox(height: 8),
                Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('검색 후 지도에서 장소를 선택해주세요.'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (_showSearchHereButton)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: FilledButton.icon(
                onPressed: _isSearching ? null : _searchHere,
                icon: const Icon(Icons.search),
                label: const Text('이 위치에서 검색'),
              ),
            ),
          ),
        if (_selectedFacility != null)
          Positioned.fill(
            child: FacilityDetailPage(
              result: _selectedFacility!,
              onClose: _closeFacilityDetail,
            ),
          ),
        ],
      ),
    );
  }
}

/// Standalone page for the "장소 선택" flow (모임 게시글): wraps the map in
/// its own Scaffold/AppBar and pops with the picked [FacilityResult].
class FacilityPickerPage extends StatelessWidget {
  const FacilityPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('장소 선택')),
      body: FacilitySearchPage(
        onPicked: (result) => Navigator.of(context).pop(result),
      ),
    );
  }
}

class FacilityDetailPage extends StatefulWidget {
  const FacilityDetailPage({super.key, required this.result, required this.onClose});

  final FacilityResult result;

  /// Called instead of a Navigator pop — this page is shown as an in-place
  /// overlay over [FacilitySearchPage], not a pushed route (see
  /// _openFacilityDetail).
  final VoidCallback onClose;

  @override
  State<FacilityDetailPage> createState() => _FacilityDetailPageState();
}

const _checkinValidFor = Duration(hours: 3);

class _FacilityDetailPageState extends State<FacilityDetailPage> {
  bool? _isFavorite;
  bool _isToggling = false;

  String? _facilityId;
  bool? _checkedIn;
  int? _checkinCount;
  bool _isCheckingInOut = false;
  RealtimeChannel? _checkinChannel;
  List<Map<String, dynamic>>? _upcomingMeetups;

  @override
  void initState() {
    super.initState();
    _loadFavoriteStatus();
    _initCheckins();
  }

  @override
  void dispose() {
    final channel = _checkinChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _initCheckins() async {
    final client = Supabase.instance.client;
    final result = widget.result;

    String facilityId;
    if (result.id != null) {
      facilityId = result.id!;
    } else {
      final (sido, sigungu) = parseRegionFromAddress(result.address);
      final facility = await client
          .from('facilities')
          .upsert({
            'name': result.name,
            'address': result.address,
            'lat': result.lat,
            'lng': result.lng,
            'category': result.category,
            'telephone': result.telephone,
            'region_sido': sido,
            'region_sigungu': sigungu,
          }, onConflict: 'name,address')
          .select('id')
          .single();
      facilityId = facility['id'] as String;
    }
    if (!mounted) return;
    setState(() => _facilityId = facilityId);

    await _refreshCheckinState();
    await _loadUpcomingMeetups(facilityId);

    _checkinChannel = client
        .channel('checkins_$facilityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'checkins',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'facility_id',
            value: facilityId,
          ),
          callback: (_) => _refreshCheckinState(),
        )
        .subscribe();
  }

  Future<void> _refreshCheckinState() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;
    final since = DateTime.now()
        .subtract(_checkinValidFor)
        .toUtc()
        .toIso8601String();

    final rows = await client
        .from('checkins')
        .select('user_id')
        .eq('facility_id', facilityId)
        .gte('checked_in_at', since);
    if (!mounted) return;
    setState(() {
      _checkinCount = rows.length;
      _checkedIn = rows.any((row) => row['user_id'] == userId);
    });
  }

  Future<void> _loadUpcomingMeetups(String facilityId) async {
    final result = await Supabase.instance.client
        .from('posts')
        .select('id, title, event_at')
        .eq('facility_id', facilityId)
        .gte('event_at', DateTime.now().toUtc().toIso8601String())
        .order('event_at');
    if (mounted) {
      setState(
        () => _upcomingMeetups = List<Map<String, dynamic>>.from(result),
      );
    }
  }

  String _formatEventAt(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}.${dt.day} ${dt.hour}:$minute';
  }

  Future<void> _toggleCheckin() async {
    final facilityId = _facilityId;
    if (facilityId == null) return;

    setState(() => _isCheckingInOut = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      if (_checkedIn == true) {
        await client
            .from('checkins')
            .delete()
            .eq('user_id', userId)
            .eq('facility_id', facilityId);
      } else {
        await client.from('checkins').upsert({
          'user_id': userId,
          'facility_id': facilityId,
          'checked_in_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'user_id,facility_id');
      }
      await _refreshCheckinState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('처리에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCheckingInOut = false);
    }
  }

  Future<void> _loadFavoriteStatus() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final rows = await Supabase.instance.client
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('name', widget.result.name)
        .eq('address', widget.result.address);
    if (mounted) setState(() => _isFavorite = rows.isNotEmpty);
  }

  Future<void> _toggleFavorite() async {
    setState(() => _isToggling = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final result = widget.result;
      if (_isFavorite == true) {
        await Supabase.instance.client
            .from('favorites')
            .delete()
            .eq('user_id', userId)
            .eq('name', result.name)
            .eq('address', result.address);
      } else {
        await Supabase.instance.client.from('favorites').insert({
          'user_id': userId,
          'name': result.name,
          'address': result.address,
          'telephone': result.telephone,
          'lat': result.lat,
          'lng': result.lng,
          'category': result.category,
        });
      }
      if (mounted) setState(() => _isFavorite = !(_isFavorite ?? false));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('즐겨찾기 처리에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onClose,
        ),
        title: Text(result.name),
        actions: [
          IconButton(
            onPressed: _isFavorite == null || _isToggling
                ? null
                : _toggleFavorite,
            icon: Icon(
              _isFavorite == true ? Icons.favorite : Icons.favorite_border,
              color: _isFavorite == true ? Colors.red : null,
            ),
            tooltip: '즐겨찾기',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.address, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              '약 ${(result.distanceMeters / 1000).toStringAsFixed(1)}km',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (result.telephone.isNotEmpty) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse('tel:${result.telephone}')),
                icon: const Icon(Icons.call),
                label: Text('${result.telephone} 전화 걸기'),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                OutlinedButton.icon(
                  // Overrides the app theme's OutlinedButton default of
                  // minimumSize: Size.fromHeight(56) (full-width: infinite
                  // minWidth). That's fine as the sole/stretched child of a
                  // Column, but inside a Row a non-flex child is given an
                  // unbounded maxWidth, so an infinite minWidth survives
                  // BoxConstraints.enforce() unclamped and crashes layout
                  // ("BoxConstraints forces an infinite width").
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _facilityId == null || _isCheckingInOut
                      ? null
                      : _toggleCheckin,
                  icon: Icon(
                    _checkedIn == true
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                  ),
                  label: Text(_checkedIn == true ? '나 여기 있음 취소' : '나 여기 있음'),
                ),
                const SizedBox(width: 12),
                if (_checkinCount != null)
                  Text(
                    '현재 $_checkinCount명 있음',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
            if (_upcomingMeetups != null && _upcomingMeetups!.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                '여기서 열리는 모임',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final meetup in _upcomingMeetups!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(meetup['title'] as String),
                  subtitle: Text(_formatEventAt(meetup['event_at'] as String)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          PostDetailPage(postId: meetup['id'] as String),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
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

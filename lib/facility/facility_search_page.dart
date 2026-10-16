import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../community/post_detail_page.dart';
import '../core/address_region.dart';
import '../ui/design_widgets.dart';
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
  final _searchController = TextEditingController();
  String? _category;
  String? _subcategory;
  // Whatever the most recent search was for — a category, a hospital
  // subcategory, or free text — regardless of which of those triggered it.
  // Drives "이 위치에서 검색" and re-search after panning.
  String? _activeSearchTerm;
  bool _isSearching = false;
  // Shown after the user manually pans/zooms the map (not after our own
  // post-search recenter), so they can re-search around wherever they
  // scrolled to instead of always their GPS location.
  bool _showSearchHereButton = false;
  // Shown as an in-place overlay (not a pushed route) so the NaverMap
  // PlatformView underneath is never touched by a Navigator transition —
  // see _openFacilityDetail for why.
  late FacilityResult? _selectedFacility = widget.initialFacility;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectCategory(String category) {
    // Picking a top-level category (e.g. re-tapping "병원") resets any
    // hospital specialty filter and searches the broad category again, and
    // clears any typed keyword search so the two don't mix.
    _searchController.clear();
    setState(() {
      _category = category;
      _subcategory = null;
    });
    _searchAtCamera(category);
  }

  void _selectSubcategory(String subcategory) {
    _searchController.clear();
    setState(() => _subcategory = subcategory);
    _searchAtCamera(subcategory);
  }

  void _submitTextSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    // A typed keyword isn't one of the category chips, so clear those to
    // avoid showing a chip selected that no longer matches what's searched.
    setState(() {
      _category = null;
      _subcategory = null;
    });
    _searchAtCamera(query);
  }

  Future<void> _searchHere() async {
    final searchTerm = _activeSearchTerm;
    if (searchTerm == null) return;
    await _searchAtCamera(searchTerm);
  }

  // Every search — whether from tapping a category or the "이 위치에서 검색"
  // button — is centered on wherever the map is currently showing, not the
  // device's live GPS. Only the very first frame (native "follow" mode set
  // in onMapReady) centers the map on the real current location; after
  // that, panning the map is what decides where searches look.
  Future<void> _searchAtCamera(String searchTerm) async {
    final controller = _controller;
    if (controller == null) return;
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
      _activeSearchTerm = searchTerm;
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
            // Set before any tracking starts so the built-in location
            // button goes through it too (see _SafeLocationTracker).
            controller.setMyLocationTracker(_SafeLocationTracker());
            final status = await Permission.location.request();
            // The page may have been left while the permission prompt was
            // up, in which case the controller is already disposed.
            if (!mounted) return;
            if (status.isGranted) {
              controller.setLocationTrackingMode(NLocationTrackingMode.follow);
            }
          },
          onCameraChange: (reason, animated) {
            final userMoved =
                reason == NCameraUpdateReason.gesture ||
                reason == NCameraUpdateReason.control;
            if (userMoved && _activeSearchTerm != null && !_showSearchHereButton) {
              setState(() => _showSearchHereButton = true);
            }
          },
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: _searchController,
                isSearching: _isSearching,
                onSubmitted: _submitTextSearch,
              ),
              const SizedBox(height: 10),
              _CategoryBar(
                selected: _category,
                isSearching: _isSearching,
                onSelected: _selectCategory,
              ),
              if (_category == '병원') ...[
                const SizedBox(height: 10),
                _CategoryBar(
                  categories: kHospitalSubcategories,
                  selected: _subcategory,
                  isSearching: _isSearching,
                  onSelected: _selectSubcategory,
                ),
              ],
              if (widget.onPicked != null) ...[
                const SizedBox(height: 10),
                Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _floatShadow,
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      '검색 후 지도에서 장소를 선택해주세요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
              if (_showSearchHereButton) ...[
                const SizedBox(height: 10),
                Center(
                  child: _SearchHereButton(
                    onPressed: _isSearching ? null : _searchHere,
                  ),
                ),
              ],
            ],
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
      backgroundColor: AppColors.background,
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
              color: _isFavorite == true ? AppColors.danger : null,
            ),
            tooltip: '즐겨찾기',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(
                    icon: Icons.place_outlined,
                    text: result.address,
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.directions_walk,
                    text:
                        '약 ${(result.distanceMeters / 1000).toStringAsFixed(1)}km',
                  ),
                  if (result.telephone.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () =>
                          launchUrl(Uri.parse('tel:${result.telephone}')),
                      icon: const Icon(Icons.call),
                      label: Text('${result.telephone} 전화 걸기'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              padding: const EdgeInsets.all(20),
              child: Row(
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
                    Flexible(
                      child: Text(
                        '현재 $_checkinCount명 있음',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
            if (_upcomingMeetups != null && _upcomingMeetups!.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                header: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '여기서 열리는 모임',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                child: Column(
                  children: [
                    for (final meetup in _upcomingMeetups!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const IconBadge(icon: Icons.event),
                        title: Text(
                          meetup['title'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          _formatEventAt(meetup['event_at'] as String),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppColors.textTertiary,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PostDetailPage(postId: meetup['id'] as String),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}

const _floatShadow = <BoxShadow>[
  BoxShadow(color: Color(0x14111827), blurRadius: 10, offset: Offset(0, 2)),
];

class _SearchHereButton extends StatelessWidget {
  const _SearchHereButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: _floatShadow,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 20,
                    color: onPressed == null
                        ? AppColors.textTertiary
                        : AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '이 위치에서 검색',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: onPressed == null
                          ? AppColors.textTertiary
                          : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.isSearching,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: _floatShadow,
      ),
      child: SizedBox(
        height: 56,
        child: TextField(
          controller: controller,
          enabled: !isSearching,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSubmitted(),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: '시설 이름으로 검색 (예: 서울대병원)',
            hintStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
            prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
            suffixIcon: Padding(
              padding: const EdgeInsets.all(6),
              child: Material(
                color: AppColors.tint,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: isSearching ? null : onSubmitted,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.arrow_forward,
                      color: isSearching
                          ? AppColors.textTertiary
                          : AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
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
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: _floatShadow,
                ),
                child: ChoiceChip(
                  label: Text(category),
                  selected: selected == category,
                  onSelected: isSearching ? null : (_) => onSelected(category),
                ),
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
    );
  }
}

/// Works around a flutter_naver_map 1.4.4 race: if the map is disposed while
/// the tracker is still waiting for the first GPS fix, the plugin starts the
/// location/heading subscriptions *after* its own cleanup already ran. They
/// then call into the dead map forever, flooding the log with
/// `MissingPluginException ... lo"L"bearing` (upstream issue #359).
///
/// Returning null from [startLocationService] makes the plugin skip starting
/// those subscriptions, so nothing is left behind.
class _SafeLocationTracker extends NDefaultMyLocationTracker {
  bool _stopped = false;

  @override
  Future<NLatLng?> startLocationService() async {
    _stopped = false;
    final location = await super.startLocationService();
    return _stopped ? null : location;
  }

  // Called by the plugin when tracking stops — either the map is disposed
  // or the location button cycles to "none".
  @override
  void disposeLocationService() {
    _stopped = true;
    super.disposeLocationService();
  }
}

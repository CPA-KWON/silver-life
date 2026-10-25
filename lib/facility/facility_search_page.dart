import 'dart:async';

import 'package:flutter/material.dart';

import '../activity/activity_hub_page.dart';

import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/phone_call.dart';
import '../community/new_post_page.dart';
import '../meetup/new_meetup_page.dart';
import '../core/meetup_category.dart';

import '../app_theme.dart';
import '../community/post_detail_page.dart';
import 'facility_repository.dart';
import '../ui/design_widgets.dart';
import 'local_facility_search.dart';
import 'naver_local_search.dart';
import 'safe_map_location_tracker.dart';
import 'welfare_programs.dart';

const kFacilityCategories = ['병원', '약국', '경로당', '복지관'];
const kHospitalSubcategories = ['내과', '정형외과', '안과', '치과', '이비인후과', '피부과'];

class FacilitySearchPage extends StatefulWidget {
  const FacilitySearchPage({
    super.key,
    this.onPicked,
    this.initialFacility,
    this.isActive = true,
    this.mapPlaceholder,
    this.enableRealtime = true,
    this.showDetailBackButton = true,
  });

  /// Pause location tracking while the map tab is hidden.
  final bool isActive;

  /// When set, tapping a marker calls this with the picked facility instead
  /// of opening the detail sheet — used by the "장소 선택" flow for meetup
  /// posts (see [FacilityPickerPage]).
  final ValueChanged<FacilityResult>? onPicked;

  /// When set, the detail overlay opens immediately showing this facility —
  /// used when arriving here from outside the map (e.g. tapping a favorite
  /// on the home tab) instead of by tapping a marker.
  final FacilityResult? initialFacility;
  final Widget? mapPlaceholder;
  final bool enableRealtime;
  final bool showDetailBackButton;

  @override
  State<FacilitySearchPage> createState() => _FacilitySearchPageState();
}

class _FacilitySearchPageState extends State<FacilitySearchPage> {
  static const _seoulCityHall = NLatLng(37.5666, 126.979);

  NaverMapController? _controller;
  late final _locationTracker = SafeMapLocationTracker(
    onLocationUnavailable: () {
      if (!mounted || !widget.isActive) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 확인하지 못했어요. 지도는 이동해서 검색할 수 있어요.')),
      );
    },
  );
  NLocationTrackingMode _resumeTrackingMode = NLocationTrackingMode.none;
  bool _trackingConfigured = false;
  // Bumped when leaving the tab so a search still in flight cannot bring
  // back markers or errors after the reset.
  int _searchSession = 0;
  bool _checkingPermission = false;
  final _searchController = TextEditingController();
  String? _category;
  String? _subcategory;
  // Whatever the most recent search was for — a category, a hospital
  // subcategory, or free text — regardless of which of those triggered it.
  // Drives "이 위치에서 검색" and re-search after panning.
  String? _activeSearchTerm;
  bool _isSearching = false;
  Object? _searchError;
  // Shown after the user manually pans/zooms the map (not after our own
  // post-search recenter), so they can re-search around wherever they
  // scrolled to instead of always their GPS location.
  bool _showSearchHereButton = false;
  // Shown as an in-place overlay (not a pushed route) so the NaverMap
  // PlatformView underneath is never touched by a Navigator transition —
  // see _openFacilityDetail for why.
  late FacilityResult? _selectedFacility = widget.initialFacility;

  String? _postId;
  Widget? _editor;
  Completer<bool?>? _editResult;
  Completer<FacilityResult?>? _placeResult;
  int _detailVersion = 0;
  void _finishEditor(bool changed) {
    final result = _editResult;
    setState(() {
      _editor = null;
      _editResult = null;
    });
    if (result != null && !result.isCompleted) result.complete(changed);
  }

  Future<bool?> _editInPlace(Map<String, dynamic> post) {
    final result = Completer<bool?>();
    final data = {...post, 'facility': post['facilities']};
    setState(() {
      _editResult = result;
      _editor = post['category'] == kMeetupCategory
          ? NewMeetupPage(
              existingPost: data,
              onFinished: _finishEditor,
              facilityPicker: _pickInPlace,
            )
          : NewPostPage(existingPost: data, onFinished: _finishEditor);
    });
    return result.future;
  }

  Future<FacilityResult?> _pickInPlace() {
    final result = Completer<FacilityResult?>();
    setState(() {
      _placeResult = result;
    });
    return result.future;
  }

  void _pickedInPlace(FacilityResult? place) {
    final result = _placeResult;
    setState(() {
      _placeResult = null;
    });
    if (result != null && !result.isCompleted) result.complete(place);
  }

  void _backInPlace() {
    if (_placeResult != null) {
      _pickedInPlace(null);
    } else if (_editor != null) {
      _finishEditor(false);
    } else if (_postId != null) {
      setState(() {
        _postId = null;
        _detailVersion++;
      });
    } else {
      _closeFacilityDetail();
    }
  }

  @override
  void didUpdateWidget(covariant FacilitySearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    // The previous implementation closed details when leaving the tab. Keep
    // that behavior and release its realtime subscription while retaining map.
    if (!widget.isActive) {
      _selectedFacility = null;
      _postId = null;
      _pickedInPlace(null);
      _finishEditor(false);
      _resetSearch();
    }
    final controller = _controller;
    _locationTracker.setActive(widget.isActive);
    if (controller == null) return;
    if (widget.isActive) {
      if (_trackingConfigured) {
        controller.setLocationTrackingMode(_resumeTrackingMode);
      } else {
        unawaited(_startInitialTracking());
      }
    } else {
      // A search may have moved the camera off the user; follow them again
      // on return when location was allowed.
      if (_resumeTrackingMode != NLocationTrackingMode.none ||
          controller.locationTrackingMode != NLocationTrackingMode.none) {
        _resumeTrackingMode = NLocationTrackingMode.follow;
      }
      controller.setLocationTrackingMode(NLocationTrackingMode.none);
    }
  }

  // Leaving the tab starts the next visit fresh: no old markers, keyword,
  // category or error.
  void _resetSearch() {
    _searchSession++;
    _searchController.clear();
    _category = null;
    _subcategory = null;
    _activeSearchTerm = null;
    _searchError = null;
    _showSearchHereButton = false;
    _isSearching = false;
    _controller
        ?.clearOverlays(type: NOverlayType.marker)
        .then((_) {}, onError: (Object _) {});
  }

  bool _stale(NaverMapController controller, int session) =>
      !mounted ||
      !identical(controller, _controller) ||
      session != _searchSession;

  Future<void> _startInitialTracking() async {
    final controller = _controller;
    if (controller == null || !widget.isActive || _checkingPermission) return;
    _checkingPermission = true;
    try {
      final status = await Permission.location.request();
      if (!mounted || !identical(controller, _controller)) return;
      _trackingConfigured = true;
      _resumeTrackingMode = status.isGranted
          ? NLocationTrackingMode.follow
          : NLocationTrackingMode.none;
      if (widget.isActive) {
        controller.setLocationTrackingMode(_resumeTrackingMode);
      }
    } catch (_) {
      _locationTracker.onLocationUnavailable?.call();
    } finally {
      _checkingPermission = false;
    }
  }

  @override
  void dispose() {
    _locationTracker.setActive(false);
    _controller = null;
    if (_editResult != null && !_editResult!.isCompleted) {
      _editResult!.complete(null);
    }
    if (_placeResult != null && !_placeResult!.isCompleted) {
      _placeResult!.complete(null);
    }
    _searchController.dispose();
    super.dispose();
  }

  void _selectCategory(String category) {
    if (_isSearching) return;
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
    if (_isSearching) return;
    _searchController.clear();
    setState(() => _subcategory = subcategory);
    _searchAtCamera(subcategory);
  }

  void _submitTextSearch() {
    if (_isSearching) return;
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
    if (controller == null || _isSearching || !widget.isActive) return;
    final session = _searchSession;

    setState(() {
      _isSearching = true;
      _showSearchHereButton = false;
      _activeSearchTerm = searchTerm;
      _searchError = null;
    });

    try {
      // A new category must never keep the previous category's markers,
      // including when the next server request fails.
      await controller
          .clearOverlays(type: NOverlayType.marker)
          .timeout(const Duration(seconds: 3));
      if (_stale(controller, session)) return;
      final position = await controller.getCameraPosition().timeout(
        const Duration(seconds: 3),
      );
      if (_stale(controller, session)) return;
      final lat = position.target.latitude;
      final lng = position.target.longitude;
      final results = kLocallySourcedCategories.contains(nearbyTerm(searchTerm))
          ? await searchOwnFacilities(
              category: nearbyTerm(searchTerm)!,
              lat: lat,
              lng: lng,
            ).timeout(const Duration(seconds: 10))
          : await searchNearbyFacilities(
              category: searchTerm,
              lat: lat,
              lng: lng,
            );

      if (_stale(controller, session)) return;
      final markers = <NMarker>{};
      for (final result in results) {
        if (_stale(controller, session)) return;
        final marker = NMarker(
          id: '${result.lat},${result.lng},${result.name}',
          position: NLatLng(result.lat, result.lng),
          caption: NOverlayCaption(text: result.name),
        );
        marker.setOnTapListener((_) {
          if (!mounted ||
              !widget.isActive ||
              _isSearching ||
              _activeSearchTerm != searchTerm) {
            return;
          }
          if (_placeResult != null) {
            _pickedInPlace(result);
          } else if (widget.onPicked != null) {
            widget.onPicked!(result);
          } else {
            _openFacilityDetail(result);
          }
        });
        markers.add(marker);
      }

      if (markers.isNotEmpty) {
        await controller
            .addOverlayAll(markers)
            .timeout(const Duration(seconds: 3));
      }
      if (_stale(controller, session)) return;

      if (results.isNotEmpty && mounted) {
        await controller
            .updateCamera(
              NCameraUpdate.withParams(
                target: NLatLng(results.first.lat, results.first.lng),
                zoom: 15,
              ),
            )
            .timeout(const Duration(seconds: 3));
      } else if (mounted && widget.isActive) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                nearbyTerm(searchTerm) == null
                    ? '"$searchTerm"을(를) 찾지 못했어요. 이름을 다시 확인해 주세요.'
                    : '주변 5km 안에서 "$searchTerm"을(를) 찾지 못했어요. 지도를 옮긴 뒤 "이 위치에서 검색"을 눌러 보세요.',
              ),
            ),
          );
      }
    } catch (error) {
      if (!_stale(controller, session)) setState(() => _searchError = error);
    } finally {
      if (mounted && session == _searchSession) {
        setState(() => _isSearching = false);
      }
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
    if (!mounted || !widget.isActive) return;
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
      canPop:
          !widget.isActive ||
          _selectedFacility == null &&
              _postId == null &&
              _editor == null &&
              _placeResult == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isActive) _backInPlace();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.mapPlaceholder ??
              NaverMap(
                options: const NaverMapViewOptions(
                  initialCameraPosition: NCameraPosition(
                    target: _seoulCityHall,
                    zoom: 14,
                  ),
                  locationButtonEnable: true,
                ),
                onMapReady: (controller) {
                  if (!mounted) return;
                  setState(() => _controller = controller);
                  _locationTracker.setActive(widget.isActive);
                  controller.setMyLocationTracker(_locationTracker);
                  if (widget.isActive) unawaited(_startInitialTracking());
                },
                onCameraChange: (reason, animated) {
                  final userMoved =
                      reason == NCameraUpdateReason.gesture ||
                      reason == NCameraUpdateReason.control;
                  if (userMoved &&
                      _activeSearchTerm != null &&
                      !_showSearchHereButton) {
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
                  isSearching:
                      _isSearching ||
                      (_controller == null && widget.mapPlaceholder == null),
                  onSubmitted: _submitTextSearch,
                ),
                const SizedBox(height: 10),
                _CategoryBar(
                  selected: _category,
                  isSearching:
                      _isSearching ||
                      (_controller == null && widget.mapPlaceholder == null),
                  onSelected: _selectCategory,
                ),
                if (_category == '병원') ...[
                  const SizedBox(height: 10),
                  _CategoryBar(
                    categories: kHospitalSubcategories,
                    selected: _subcategory,
                    isSearching:
                        _isSearching ||
                        (_controller == null && widget.mapPlaceholder == null),
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
          if (_searchError != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: _placeResult == null ? 16 : 96,
              child: Material(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surface,
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(facilitySearchErrorMessage(_searchError!)),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _isSearching
                            ? null
                            : () {
                                if (_searchError
                                    is FacilitySearchNotReadyException) {
                                  _selectCategory('경로당');
                                } else {
                                  _searchAtCamera(_activeSearchTerm!);
                                }
                              },
                        child: Text(
                          _searchError is FacilitySearchNotReadyException
                              ? '경로당 보기'
                              : '다시 시도',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_selectedFacility != null)
            Positioned.fill(
              child: Offstage(
                offstage:
                    _postId != null || _editor != null || _placeResult != null,
                child: FacilityDetailPage(
                  result: _selectedFacility!,
                  onClose: _closeFacilityDetail,
                  onOpenPost: (id) => setState(() {
                    _postId = id;
                  }),
                  enableRealtime: widget.enableRealtime,
                  refreshVersion: _detailVersion,
                  showBackButton: widget.showDetailBackButton,
                ),
              ),
            ),
          if (_postId != null)
            Positioned.fill(
              child: Offstage(
                offstage: _editor != null || _placeResult != null,
                child: PostDetailPage(
                  postId: _postId!,
                  onClose: _backInPlace,
                  onEdit: _editInPlace,
                ),
              ),
            ),
          if (_editor != null)
            Positioned.fill(
              child: Offstage(offstage: _placeResult != null, child: _editor!),
            ),
          if (_placeResult != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: FilledButton(
                onPressed: () => _pickedInPlace(null),
                child: const Text('장소 선택 취소'),
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
  const FacilityDetailPage({
    super.key,
    required this.result,
    required this.onClose,
    this.onOpenPost,
    this.enableRealtime = true,
    this.refreshVersion = 0,
    this.showBackButton = true,
  });

  final FacilityResult result;
  final ValueChanged<String>? onOpenPost;
  final bool enableRealtime;
  final int refreshVersion;
  final bool showBackButton;

  /// Called instead of a Navigator pop — this page is shown as an in-place
  /// overlay over [FacilitySearchPage], not a pushed route (see
  /// _openFacilityDetail).
  final VoidCallback onClose;

  @override
  State<FacilityDetailPage> createState() => _FacilityDetailPageState();
}

class _FacilityDetailPageState extends State<FacilityDetailPage> {
  bool? _isFavorite;
  bool _isToggling = false;

  /// What favorites and check-ins save: [FacilityDetailPage.result] itself,
  /// or its NAVER match when the result is live-only Kakao data.
  FacilityResult? _storable;
  bool _notStorable = false;

  String? _facilityId;
  bool? _checkedIn;
  int? _checkinCount;
  bool _isCheckingInOut = false;
  RealtimeChannel? _checkinChannel;
  List<Map<String, dynamic>>? _upcomingMeetups;
  bool _loadingDetails = false;
  bool _detailLoadFailed = false;
  int _detailGeneration = 0;
  int _checkinRefresh = 0;

  Timer? _expiryTimer;
  void _safeRefresh() {
    _refreshCheckinState().catchError((Object _) {});
  }

  @override
  void didUpdateWidget(covariant FacilityDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshVersion != widget.refreshVersion) _loadDetails();
  }

  @override
  void initState() {
    super.initState();
    _loadDetails();
    _expiryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _safeRefresh(),
    );
  }

  @override
  void dispose() {
    _detailGeneration++;
    _expiryTimer?.cancel();
    final channel = _checkinChannel;
    if (channel != null) Supabase.instance.client.removeChannel(channel);
    super.dispose();
  }

  Future<void> _loadDetails() async {
    if (_loadingDetails) return;
    final generation = ++_detailGeneration;
    setState(() {
      _loadingDetails = true;
      _detailLoadFailed = false;
    });
    final oldChannel = _checkinChannel;
    _checkinChannel = null;
    if (oldChannel != null) {
      unawaited(Supabase.instance.client.removeChannel(oldChannel));
    }
    try {
      if (_storable == null) {
        try {
          final storable = await findStorableFacility(widget.result);
          if (!mounted || generation != _detailGeneration) return;
          setState(() => _storable = storable);
        } on FacilityNotStorableException {
          if (mounted && generation == _detailGeneration) {
            setState(() => _notStorable = true);
          }
          return;
        }
      }
      await Future.wait([
        _loadFavoriteStatus(generation),
        _initCheckins(generation),
      ]);
    } catch (_) {
      if (!mounted || generation != _detailGeneration) return;
      // Invalidate late responses before allowing a retry.
      _detailGeneration++;
      final channel = _checkinChannel;
      _checkinChannel = null;
      if (channel != null) {
        unawaited(Supabase.instance.client.removeChannel(channel));
      }
      setState(() => _detailLoadFailed = true);
    } finally {
      if (mounted) setState(() => _loadingDetails = false);
    }
  }

  Future<void> _initCheckins(int generation) async {
    final client = Supabase.instance.client;
    final result = _storable!;

    String facilityId;
    if (result.id != null) {
      facilityId = result.id!;
    } else {
      facilityId = await ensureFacility(result);
    }
    if (!mounted || generation != _detailGeneration) return;
    setState(() => _facilityId = facilityId);

    // Register before awaiting reads, so closing during a read cannot create
    // an orphan subscription after dispose. The reads run independently.
    if (widget.enableRealtime) {
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
            callback: (_) async {
              if (!mounted || generation != _detailGeneration) return;
              try {
                await _refreshCheckinState();
              } catch (_) {
                if (mounted) setState(() => _detailLoadFailed = true);
              }
            },
          )
          .subscribe();
    }
    await Future.wait([
      _refreshCheckinState(),
      _loadUpcomingMeetups(facilityId),
    ]);
  }

  Future<void> _refreshCheckinState() async {
    final generation = _detailGeneration;
    final refresh = ++_checkinRefresh;
    final facilityId = _facilityId;
    if (facilityId == null) return;
    final client = Supabase.instance.client;

    final summary = await client
        .rpc('facility_presence', params: {'target_facility': facilityId})
        .timeout(const Duration(seconds: 10));
    if (!mounted ||
        generation != _detailGeneration ||
        refresh != _checkinRefresh) {
      return;
    }
    setState(() {
      _checkinCount = (summary['count'] as num).toInt();
      _checkedIn = summary['checked_in'] as bool;
    });
  }

  Future<void> _loadUpcomingMeetups(String facilityId) async {
    final generation = _detailGeneration;
    final result = await Supabase.instance.client
        .from('posts')
        .select('id, title, event_at')
        .eq('facility_id', facilityId)
        .gte('event_at', DateTime.now().toUtc().toIso8601String())
        .order('event_at')
        .timeout(const Duration(seconds: 10));
    if (mounted && generation == _detailGeneration) {
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
    if (facilityId == null || _checkedIn == null || _isCheckingInOut) return;

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

  Future<void> _loadFavoriteStatus(int generation) async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final rows = await Supabase.instance.client
        .from('favorites')
        .select('id')
        .eq('user_id', userId)
        .eq('name', _storable!.name)
        .eq('address', _storable!.address)
        .timeout(const Duration(seconds: 10));
    if (mounted && generation == _detailGeneration) {
      setState(() => _isFavorite = rows.isNotEmpty);
    }
  }

  Future<void> _toggleFavorite() async {
    if (_isToggling || _isFavorite == null) return;
    setState(() => _isToggling = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final result = _storable!;
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
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onClose,
              )
            : null,
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
            if (_detailLoadFailed) ...[
              SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('시설 정보를 불러오지 못했어요. 다시 시도해 주세요.'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _loadingDetails ? null : _loadDetails,
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_notStorable) ...[
              const SectionCard(
                padding: EdgeInsets.all(16),
                child: Text(
                  '이 시설은 즐겨찾기와 "나 여기 있음"을 쓸 수 없어요. '
                  '전화 걸기와 위치 확인은 그대로 할 수 있어요.',
                ),
              ),
              const SizedBox(height: 12),
            ],
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
                  _InfoRow(icon: Icons.place_outlined, text: result.address),
                  const SizedBox(height: 10),
                  _InfoRow(
                    icon: Icons.directions_walk,
                    text: result.distanceMeters.isFinite
                        ? '약 ${(result.distanceMeters / 1000).toStringAsFixed(1)}km'
                        : '거리는 지도에서 위치를 확인해주세요.',
                  ),
                  if (result.telephone.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () => callFacility(context, result.telephone),
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
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    // Overrides the app theme's OutlinedButton default of
                    // minimumSize: Size.fromHeight(56) (full-width: infinite
                    // minWidth). That's fine as the sole/stretched child of a
                    // Column, but inside a Row a non-flex child is given an
                    // unbounded maxWidth, so an infinite minWidth survives
                    // BoxConstraints.enforce() unclamped and crashes layout
                    // ("BoxConstraints forces an infinite width").
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    onPressed:
                        _facilityId == null ||
                            _checkedIn == null ||
                            _isCheckingInOut
                        ? null
                        : _toggleCheckin,
                    icon: Icon(
                      _checkedIn == true
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                    ),
                    label: Text(_checkedIn == true ? '나 여기 있음 취소' : '나 여기 있음'),
                  ),
                  if (_checkinCount != null)
                    Text(
                      '현재 $_checkinCount명 있음',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActivitySectionPage(
                    section: ActivitySection.programs,
                    place: (
                      name: result.name,
                      lat: result.lat,
                      lng: result.lng,
                    ),
                  ),
                ),
              ),
              icon: const Icon(Icons.event_note),
              label: const Text('앱으로 신청하는 활동'),
            ),
            WelfareProgramsSection(
              facilityName: result.name,
              telephone: result.telephone,
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
                        onTap: () => widget.onOpenPost != null
                            ? widget.onOpenPost!(meetup['id'] as String)
                            : Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PostDetailPage(
                                    postId: meetup['id'] as String,
                                  ),
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
                      fontSize: 18,
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
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: '시설 이름으로 검색 (예: 서울대병원)',
            hintStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.textSecondary,
            ),
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

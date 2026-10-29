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
import 'naver_local_search.dart';
import 'safe_map_location_tracker.dart';
import 'welfare_programs.dart';
import 'facility_distance.dart';
import 'facility_catalog.dart';
import 'facility_flow.dart';
import 'facility_program_preview.dart';
import '../activity/activity_detail_page.dart';
import '../activity/activity_welfare_detail.dart';
import '../activity/activity_repository.dart';
import '../social/photo_widgets.dart';
import 'facility_result_widgets.dart';
import '../ui/neighborhood_design.dart';
import '../attendance/point_badge.dart';
import '../core/map_directions.dart';

import 'package:geolocator/geolocator.dart';

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
    this.showHeader = false,
    this.nearbyPageBuilder,
    this.positionLoader = loadFacilityPosition,
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
  final bool showHeader;
  final WidgetBuilder? nearbyPageBuilder;
  final FacilityPositionLoader positionLoader;

  @override
  FacilitySearchPageState createState() => FacilitySearchPageState();
}

class FacilitySearchPageState extends State<FacilitySearchPage> {
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
  @override
  void initState() {
    super.initState();
    _watchMap();
  }

  void _watchMap() {
    _mapWaitTimer?.cancel();
    if (widget.mapPlaceholder == null) {
      _mapWaitTimer = Timer(const Duration(seconds: 20), () {
        if (mounted && _controller == null) setState(() => _mapFailed = true);
      });
    }
  }

  Future<void> _startMapSearch() async {
    if (_initialSearch) return;
    _initialSearch = true;
    await _startInitialTracking();
    Position? p;
    try {
      p = await widget.positionLoader();
    } catch (_) {}
    final controller = _controller;
    if (!mounted || !widget.isActive || controller == null) return;
    if (p != null) {
      setState(() => _userPosition = p);
      if (!_userMoved) {
        try {
          await controller.updateCamera(
            NCameraUpdate.withParams(
              target: NLatLng(p.latitude, p.longitude),
              zoom: 14,
            ),
          );
        } catch (_) {}
      }
    }
    if (mounted && widget.isActive) await _searchAtCamera(_category ?? '전체');
  }

  void _chooseResult(FacilityResult r) {
    if (!mounted || !widget.isActive || _isSearching) return;
    if (_placeResult != null) {
      _pickedInPlace(r);
    } else if (widget.onPicked != null) {
      widget.onPicked!(r);
    } else {
      FocusScope.of(context).unfocus();
      if (_listMode) {
        _openFacilityDetail(r);
      } else {
        setState(() => _preview = r);
      }
    }
  }

  List<FacilityResult>? _savedPlaces;
  int _searchVersion = 0;

  void showFacilities(List<FacilityResult> places, {bool detail = false}) {
    if (places.isEmpty) return;
    _searchVersion++;
    _pickedInPlace(null);
    _finishEditor(false);
    setState(() {
      _savedPlaces = places;
      _results = places;
      _isSearching = false;
      _searchError = null;
      _partialResults = false;
      _initialSearch = true;
      _userMoved = true;
      _listMode = false;
      _preview = null;
      _postId = null;
      _selectedFacility = detail ? places.first : null;
    });
    if (_controller != null) unawaited(_showSavedMarkers());
  }

  Future<void> _showSavedMarkers() async {
    final places = _savedPlaces, c = _controller, version = _searchVersion;
    if (places == null || c == null) return;
    try {
      await c.clearOverlays(type: NOverlayType.marker);
      if (!mounted || version != _searchVersion) return;
      final markers = <NMarker>{};
      for (final r in places) {
        final m = NMarker(
          id: '${r.lat},${r.lng},${r.name}',
          position: NLatLng(r.lat, r.lng),
          caption: NOverlayCaption(text: r.name),
          iconTintColor: facilityColor(r.category),
        );
        m.setOnTapListener((_) {
          if (mounted && widget.isActive && version == _searchVersion) {
            _chooseResult(r);
          }
        });
        markers.add(m);
      }
      await c.addOverlayAll(markers);
      if (!mounted || version != _searchVersion) return;
      await c.updateCamera(
        places.length == 1
            ? NCameraUpdate.withParams(
                target: NLatLng(places.first.lat, places.first.lng),
                zoom: 15,
              )
            : NCameraUpdate.fitBounds(
                NLatLngBounds.from(places.map((r) => NLatLng(r.lat, r.lng))),
                padding: const EdgeInsets.fromLTRB(40, 160, 40, 230),
              ),
      );
    } catch (_) {
      if (mounted && version == _searchVersion) {
        setState(() => _mapFailed = true);
      }
    }
  }

  NLocationTrackingMode _resumeTrackingMode = NLocationTrackingMode.none;
  bool _trackingConfigured = false;
  bool _checkingPermission = false;
  final _searchController = TextEditingController();
  String? _category = '전체';
  List<FacilityResult> _results = [];
  FacilityResult? _preview;
  Position? _userPosition;
  bool _listMode = false,
      _partialResults = false,
      _userMoved = false,
      _initialSearch = false;
  bool _mapFailed = false;
  int _mapGeneration = 0;
  Timer? _mapWaitTimer;
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
  final _flowKey = GlobalKey<NavigatorState>();
  bool _flowOpen = false;
  void _openFlow(Widget page) {
    setState(() {
      _flowOpen = true;
      _editor = FacilityFlow(
        navigatorKey: _flowKey,
        page: page,
        onClose: () {
          if (mounted) _finishEditor(false);
        },
      );
    });
  }

  void _openNearby() {
    final builder = widget.nearbyPageBuilder;
    if (builder != null) _openFlow(builder(context));
  }

  Completer<bool?>? _editResult;
  Completer<FacilityResult?>? _placeResult;
  int _detailVersion = 0;
  void _finishEditor(bool changed) {
    final result = _editResult;
    setState(() {
      _editor = null;
      _flowOpen = false;
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
      if (_flowOpen && _flowKey.currentState != null) {
        _flowKey.currentState!.maybePop();
      } else {
        _finishEditor(false);
      }
    } else if (_postId != null) {
      setState(() {
        _postId = null;
        _detailVersion++;
      });
    } else if (_selectedFacility != null) {
      _closeFacilityDetail();
    } else if (_preview != null) {
      setState(() => _preview = null);
    } else if (_listMode) {
      setState(() => _listMode = false);
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
      _preview = null;
      _postId = null;
      _pickedInPlace(null);
      _finishEditor(false);
    }
    final controller = _controller;
    _locationTracker.setActive(widget.isActive);
    if (controller == null) return;
    if (widget.isActive) {
      if (!_initialSearch) {
        unawaited(_startMapSearch());
      } else if (_trackingConfigured) {
        controller.setLocationTrackingMode(_resumeTrackingMode);
      } else {
        unawaited(_startInitialTracking());
      }
    } else {
      _resumeTrackingMode = controller.locationTrackingMode;
      controller.setLocationTrackingMode(NLocationTrackingMode.none);
    }
  }

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
    _mapWaitTimer?.cancel();
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
    final version = ++_searchVersion;
    _savedPlaces = null;

    setState(() {
      _isSearching = true;
      _showSearchHereButton = false;
      _activeSearchTerm = searchTerm;
      _searchError = null;
      _results = [];
      _preview = null;
      _partialResults = false;
    });

    try {
      // A new category must never keep the previous category's markers,
      // including when the next server request fails.
      await controller
          .clearOverlays(type: NOverlayType.marker)
          .timeout(const Duration(seconds: 3));
      if (!mounted ||
          !identical(controller, _controller) ||
          version != _searchVersion) {
        return;
      }
      final position = await controller.getCameraPosition().timeout(
        const Duration(seconds: 3),
      );
      if (!mounted ||
          !identical(controller, _controller) ||
          version != _searchVersion) {
        return;
      }
      final lat = position.target.latitude;
      final lng = position.target.longitude;
      final batch = await searchFacilityCatalog(
        category: searchTerm,
        lat: lat,
        lng: lng,
      );
      final results = batch.results;
      if (mounted && version == _searchVersion) {
        setState(() {
          _results = results;
          _partialResults = batch.partial;
        });
      }
      unawaited(() async {
        try {
          final p = await widget.positionLoader();
          if (mounted && widget.isActive) setState(() => _userPosition = p);
        } catch (_) {
          // GPS failure does not remove successfully loaded map results.
        }
      }());

      if (!mounted ||
          !identical(controller, _controller) ||
          version != _searchVersion) {
        return;
      }
      final markers = <NMarker>{};
      for (final result in results) {
        if (!mounted || _controller != controller) return;
        final marker = NMarker(
          id: '${result.lat},${result.lng},${result.name}',
          position: NLatLng(result.lat, result.lng),
          caption: NOverlayCaption(text: result.name),
          iconTintColor: facilityColor(result.category),
        );
        marker.setOnTapListener((_) {
          if (!mounted ||
              !widget.isActive ||
              _isSearching ||
              _activeSearchTerm != searchTerm) {
            return;
          }
          _chooseResult(result);
        });
        markers.add(marker);
      }

      if (markers.isNotEmpty) {
        await controller
            .addOverlayAll(markers)
            .timeout(const Duration(seconds: 3));
      }
      if (!mounted ||
          !identical(controller, _controller) ||
          version != _searchVersion) {
        return;
      }

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
            SnackBar(content: Text('주변에서 "$searchTerm"를 찾지 못했습니다.')),
          );
      }
    } catch (error) {
      if (mounted && version == _searchVersion) {
        setState(() => _searchError = error);
      }
    } finally {
      if (mounted && version == _searchVersion) {
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

  Widget _toolbar() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (widget.showHeader) ...[
        Row(
          children: [
            Expanded(
              child: Text('시설 찾기', style: petText(27, weight: FontWeight.w800)),
            ),
            if (widget.nearbyPageBuilder != null)
              TextButton(onPressed: _openNearby, child: const Text('주변 시설')),
            const PointBadge(),
          ],
        ),
        const SizedBox(height: 12),
      ],
      _SearchField(
        controller: _searchController,
        isSearching:
            _isSearching ||
            (_controller == null && widget.mapPlaceholder == null),
        onSubmitted: _submitTextSearch,
      ),
      const SizedBox(height: 10),
      _CategoryBar(
        categories: const ['전체', ...kFacilityCategories],
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
  );
  Widget _resultList() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(
        '${_activeSearchTerm ?? '시설'} 검색 결과 ${_results.length}곳',
        style: petText(19),
      ),
      Text(
        '현재 위치에서의 직선거리예요. 목록은 지도 검색 위치를 기준으로 정렬돼요.',
        style: petText(14, color: PetColors.secondary),
      ),
      const SizedBox(height: 12),
      for (final r in _results)
        FacilityResultTile(
          result: r,
          position: _userPosition,
          onTap: () => _chooseResult(r),
        ),
      if (_results.isEmpty && !_isSearching)
        const ActivityEmpty(
          '주변 시설을 찾지 못했어요',
          message: '다른 이름이나 위치로 다시 검색해 주세요.',
        ),
    ],
  );
  Widget _resultPanel() {
    final r = _preview;
    return ActivityCard(
      padding: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r == null ? '지도 주변 시설 ${_results.length}곳' : r.name,
                  style: petText(19),
                ),
              ),
              if (r == null)
                TextButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _listMode = true);
                  },
                  child: const Text('목록으로 보기 ›'),
                )
              else
                IconButton(
                  tooltip: '시설 선택 취소',
                  onPressed: () => setState(() => _preview = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_partialResults)
            Text(
              '일부 시설 정보가 늦어지고 있어요. 다시 검색해 주세요.',
              style: petText(13, color: PetColors.orange),
            ),
          if (r == null) ...[
            for (final item in _results.take(2))
              FacilityResultTile(
                result: item,
                position: _userPosition,
                onTap: () => _chooseResult(item),
              ),
          ] else ...[
            Text(r.address, style: petText(15, color: PetColors.secondary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ActivityButton(
                    '시설 상세 보기',
                    onTap: () => _openFacilityDetail(r),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ActivityButton(
                    '길 찾기',
                    light: true,
                    onTap: () => openMapDirections(
                      context,
                      name: r.name,
                      lat: r.lat,
                      lng: r.lng,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
              _placeResult == null &&
              _preview == null &&
              !_listMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.isActive) _backInPlace();
      },
      child: FacilityPickerScope(
        pick: _pickInPlace,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              excluding:
                  _selectedFacility != null ||
                  _postId != null ||
                  _editor != null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.mapPlaceholder ??
                      NaverMap(
                        key: ValueKey('facility-native-$_mapGeneration'),
                        options: const NaverMapViewOptions(
                          initialCameraPosition: NCameraPosition(
                            target: _seoulCityHall,
                            zoom: 14,
                          ),
                          locationButtonEnable: true,
                        ),
                        onMapReady: (controller) {
                          if (!mounted) return;
                          _mapWaitTimer?.cancel();
                          setState(() {
                            _controller = controller;
                            _mapFailed = false;
                          });
                          _locationTracker.setActive(widget.isActive);
                          controller.setMyLocationTracker(_locationTracker);
                          if (widget.isActive) {
                            if (_savedPlaces != null) {
                              unawaited(_showSavedMarkers());
                            } else {
                              unawaited(_startMapSearch());
                            }
                          }
                        },
                        onCameraChange: (reason, animated) {
                          final userMoved =
                              reason == NCameraUpdateReason.gesture ||
                              reason == NCameraUpdateReason.control;
                          if (userMoved) _userMoved = true;
                          if (userMoved &&
                              _activeSearchTerm != null &&
                              !_showSearchHereButton) {
                            setState(() => _showSearchHereButton = true);
                          }
                        },
                      ),
                  if (_listMode)
                    Positioned.fill(
                      child: ColoredBox(
                        color: PetColors.background,
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: _toolbar(),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _listMode = false),
                                  icon: const Icon(Icons.map_outlined),
                                  label: const Text('지도에서 보기'),
                                ),
                              ),
                            ),
                            Expanded(child: _resultList()),
                          ],
                        ),
                      ),
                    )
                  else
                    Positioned(top: 16, left: 16, right: 16, child: _toolbar()),
                  if (!_listMode &&
                      _searchError == null &&
                      (_preview != null || _results.isNotEmpty) &&
                      _placeResult == null &&
                      widget.onPicked == null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .4,
                        ),
                        child: SingleChildScrollView(child: _resultPanel()),
                      ),
                    ),
                  if (_mapFailed)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 18,
                      child: ActivityEmpty(
                        '지도를 불러오지 못했어요',
                        message:
                            '인터넷 연결을 확인한 뒤 다시 시도해 주세요. 주변 시설 목록은 계속 이용할 수 있어요.',
                        action: '지도 다시 시도',
                        onAction: () {
                          setState(() {
                            _mapGeneration++;
                            _mapFailed = false;
                            _initialSearch = false;
                            _trackingConfigured = false;
                          });
                          _watchMap();
                        },
                        secondary: widget.nearbyPageBuilder == null
                            ? null
                            : '주변 시설 목록 보기',
                        onSecondary: widget.nearbyPageBuilder == null
                            ? null
                            : _openNearby,
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
                                  _searchError
                                          is FacilitySearchNotReadyException
                                      ? '경로당 보기'
                                      : '다시 시도',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_selectedFacility != null)
              Positioned.fill(
                child: Offstage(
                  offstage:
                      _postId != null ||
                      _editor != null ||
                      _placeResult != null,
                  child: FacilityDetailPage(
                    result: _selectedFacility!,
                    onClose: _closeFacilityDetail,
                    onOpenPost: (id) => setState(() {
                      _postId = id;
                    }),
                    enableRealtime: widget.enableRealtime,
                    refreshVersion: _detailVersion,
                    showBackButton: widget.showDetailBackButton,
                    positionLoader: widget.positionLoader,
                    onOpenPrograms: () => _openFlow(
                      ActivitySectionPage(
                        section: ActivitySection.programs,
                        place: (
                          name: _selectedFacility!.name,
                          lat: _selectedFacility!.lat,
                          lng: _selectedFacility!.lng,
                        ),
                      ),
                    ),
                    onOpenProgram: (p) => _openFlow(
                      p['source'] == 'welfare'
                          ? ActivityWelfareDetailPage(program: p)
                          : ActivityDetailPage(programId: p['id']),
                    ),
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
                child: Offstage(
                  offstage: _placeResult != null,
                  child: _editor!,
                ),
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
    this.positionLoader = loadFacilityPosition,
    this.onOpenPrograms,
    this.onOpenProgram,
  });

  final VoidCallback? onOpenPrograms;
  final ValueChanged<ActivityData>? onOpenProgram;
  final FacilityResult result;
  final FacilityPositionLoader positionLoader;
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
  double? _currentDistance;
  bool _distanceLoading = true;
  bool? _isFavorite;
  bool _isToggling = false;

  String? _facilityId;
  bool? _checkedIn;
  int? _checkinCount;
  bool _isCheckingInOut = false;
  RealtimeChannel? _checkinChannel;
  List<Map<String, dynamic>>? _upcomingMeetups;
  Map<String, dynamic>? _guide;
  bool _guideError = false;
  bool _weekExpanded = false;
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
    unawaited(_loadDistance());
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

  Future<void> _loadDistance() async {
    Position? p;
    try {
      p = await widget.positionLoader();
    } catch (_) {
      /* Distance stays unknown. */
    }
    final target = widget.result;
    final valid =
        p != null &&
        p.latitude.isFinite &&
        p.longitude.isFinite &&
        p.latitude.abs() <= 90 &&
        p.longitude.abs() <= 180 &&
        target.lat.isFinite &&
        target.lng.isFinite &&
        target.lat.abs() <= 90 &&
        target.lng.abs() <= 180;
    if (!mounted) return;
    setState(() {
      _currentDistance = valid
          ? Geolocator.distanceBetween(
              p!.latitude,
              p.longitude,
              target.lat,
              target.lng,
            )
          : null;
      _distanceLoading = false;
    });
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
      await Future.wait([
        _loadFavoriteStatus(generation),
        _initCheckins(generation),
        _loadGuide(generation),
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

  Future<void> _loadGuide(int generation) async {
    try {
      final id = widget.result.id ?? await ensureFacility(widget.result);
      final raw = await Supabase.instance.client
          .rpc('facility_guide', params: {'target_facility': id})
          .timeout(const Duration(seconds: 10));
      if (mounted && generation == _detailGeneration) {
        setState(() {
          _guide = raw is Map ? Map<String, dynamic>.from(raw) : {};
          _guideError = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _detailGeneration) {
        setState(() {
          _guide = {};
          _guideError = true;
        });
      }
    }
  }

  Future<void> _initCheckins(int generation) async {
    final client = Supabase.instance.client;
    final result = widget.result;

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
        .select('id, title, event_at, meetup_cancelled')
        .eq('facility_id', facilityId)
        .gte('event_at', DateTime.now().toUtc().toIso8601String())
        .order('event_at')
        .timeout(const Duration(seconds: 10));
    if (mounted && generation == _detailGeneration) {
      setState(
        () =>
            _upcomingMeetups = List<Map<String, dynamic>>.from(result)
                .where((p) => p['meetup_cancelled'] != true)
                .toList(),
      );
    }
  }

  String _formatEventAt(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}.${dt.day} ${dt.hour}:$minute';
  }

  Future<void> _toggleCheckin() async {
    final id = _facilityId;
    if (id == null || _checkedIn == null || _isCheckingInOut) return;
    final leaving = _checkedIn == true;
    if (!await activityDialog(
      context,
      title: leaving ? '체크인을 취소할까요?' : '지금 이 시설에 계신가요?',
      message: leaving
          ? '현재 방문 표시를 지워요.'
          : '시설 200m 안에서 현재 위치를 확인해요. 체크인은 3시간 뒤 자동으로 종료돼요.',
      action: leaving ? '체크인 취소' : '체크인하기',
      icon: Icons.location_on_outlined,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _isCheckingInOut = true);
    try {
      final c = Supabase.instance.client;
      if (leaving) {
        await c
            .from('checkins')
            .delete()
            .eq('user_id', c.auth.currentUser!.id)
            .eq('facility_id', id);
      } else {
        final p = await widget.positionLoader();
        if (p == null) {
          if (mounted) {
            final settings = await activityDialog(
              context,
              title: '현재 위치를 확인해 주세요',
              message: '정확한 위치 권한과 위치 서비스를 켠 뒤 다시 시도해 주세요.',
              action: '설정 열기',
              secondary: '나중에',
              icon: Icons.location_on_outlined,
            );
            if (settings) await openAppSettings();
          }
          return;
        }
        final meters = Geolocator.distanceBetween(
          p.latitude,
          p.longitude,
          widget.result.lat,
          widget.result.lng,
        );
        if (meters > 200) {
          if (mounted) {
            final route = await activityDialog(
              context,
              title: '시설 가까이에서 체크인해 주세요',
              message:
                  '시설 200m 안에 도착한 뒤 이용할 수 있어요. ${facilityDistanceLabel(meters)}',
              action: '길 찾기',
              secondary: '닫기',
              icon: Icons.directions_walk,
            );
            if (route && mounted) {
              await openMapDirections(
                context,
                lat: widget.result.lat,
                lng: widget.result.lng,
                name: widget.result.name,
              );
            }
          }
          return;
        }
        await c.rpc(
          'facility_check_in',
          params: {
            'target_facility': id,
            'latitude': p.latitude,
            'longitude': p.longitude,
            'accuracy': p.accuracy,
            'captured_at': p.timestamp.toUtc().toIso8601String(),
          },
        );
      }
      await _refreshCheckinState();
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: leaving ? '체크인을 취소하지 못했어요' : '체크인하지 못했어요',
          message: '현재 위치와 연결 상태를 확인한 뒤 다시 시도해 주세요.',
        );
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
        .eq('name', widget.result.name)
        .eq('address', widget.result.address)
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

  void programs() {
    if (widget.onOpenPrograms != null) {
      widget.onOpenPrograms!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActivitySectionPage(
          section: ActivitySection.programs,
          place: (
            name: widget.result.name,
            lat: widget.result.lat,
            lng: widget.result.lng,
          ),
        ),
      ),
    );
  }

  void program(ActivityData p) {
    if (widget.onOpenProgram != null) {
      widget.onOpenProgram!(p);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => p['source'] == 'welfare'
            ? ActivityWelfareDetailPage(program: p)
            : ActivityDetailPage(programId: p['id']),
      ),
    );
  }

  Widget action(
    String label,
    IconData icon,
    Color color,
    VoidCallback? tap, {
    bool selected = false,
    String? tooltip,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: tooltip ?? label,
        child: ActivityCard(
          padding: 10,
          color: selected ? color.withValues(alpha: .1) : Colors.white,
          border: BorderSide(color: selected ? color : PetColors.line),
          onTap: tap,
          child: Opacity(
            opacity: tap == null ? 0.45 : 1,
            child: Column(
              children: [
                Icon(icon, color: color, size: 27),
                const SizedBox(height: 8),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: petText(15, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget information(IconData icon, String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE5F2FA),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: PetColors.blue, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: petText(14, color: PetColors.secondary)),
              const SizedBox(height: 4),
              Text(value, style: petText(17)),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final r = widget.result, g = _guide ?? <String, dynamic>{};
    final phone =
        ('${g['contact_phone'] ?? ''}'.trim().isNotEmpty
                ? '${g['contact_phone']}'
                : r.telephone)
            .trim();
    String text(String key, String unknown) =>
        '${g[key] ?? ''}'.trim().isEmpty ? unknown : '${g[key]}';
    final info = <Widget>[
      if (_detailLoadFailed)
        ActivityEmpty(
          '시설 정보를 불러오지 못했어요. 다시 시도해 주세요.',
          action: '다시 시도',
          onAction: _loadingDetails ? null : _loadDetails,
        ),
      NeighborhoodHero(
        title: r.name,
        subtitle:
            '${r.address}\n${_distanceLoading ? '현재 위치에서 거리를 확인하고 있어요' : facilityDistanceLabel(_currentDistance)}',
        color: PetColors.purple,
        tags: [
          PetPill(r.category, color: Colors.white, ink: PetColors.purple),
          if (g.isNotEmpty)
            const PetPill(
              '기관 등록 정보',
              color: Color(0xFFE4F5EB),
              ink: PetColors.green,
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          action(
            '전화',
            Icons.phone_outlined,
            PetColors.green,
            phone.isEmpty ? null : () => callFacility(context, phone),
          ),
          action(
            '길 찾기',
            Icons.directions_walk,
            PetColors.blue,
            () => openMapDirections(
              context,
              lat: r.lat,
              lng: r.lng,
              name: r.name,
            ),
          ),
          action(
            '즐겨찾기',
            _isFavorite == true ? Icons.star : Icons.star_outline,
            PetColors.orange,
            _isFavorite == null || _isToggling ? null : _toggleFavorite,
            selected: _isFavorite == true,
            tooltip: '즐겨찾기',
          ),
          action(
            _checkedIn == true ? '체크인 취소' : '체크인',
            _checkedIn == true ? Icons.check_circle : Icons.pin_drop_outlined,
            PetColors.green,
            _facilityId == null || _checkedIn == null || _isCheckingInOut
                ? null
                : _toggleCheckin,
            selected: _checkedIn == true,
          ),
        ],
      ),
      if (_checkinCount != null) ...[
        const SizedBox(height: 14),
        ActivityCard(
          color: neighborhoodMint,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _checkedIn == true ? '지금 여기 있어요' : '체크인한 이웃',
                style: petText(20, color: PetColors.green),
              ),
              Text(
                '앱에서 체크인한 이웃 ${_checkinCount ?? 0}명 · 최근 3시간',
                style: petText(15, color: PetColors.secondary),
              ),
              Text(
                '시설 전체 이용 인원이나 혼잡도는 아니에요.',
                style: petText(13, color: PetColors.secondary),
              ),
            ],
          ),
        ),
      ],
      const NeighborhoodHeading('이용 정보', color: PetColors.blue),
      ActivityCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            information(
              Icons.schedule,
              '운영시간',
              text('opening_hours', '운영시간은 아직 등록되지 않았어요. 기관에 확인해 주세요.'),
            ),
            const Divider(height: 1),
            information(
              Icons.map_outlined,
              '층별 안내',
              text('floor_guide', '층별 안내는 아직 등록되지 않았어요.'),
            ),
            const Divider(height: 1),
            information(
              Icons.phone_outlined,
              '전화',
              phone.isEmpty ? '등록된 연락처가 없어요' : phone,
            ),
            if (g.isNotEmpty) ...[
              const Divider(height: 1),
              information(
                Icons.accessible,
                '이동 편의',
                [
                  if (g['elevator'] != null)
                    '엘리베이터 ${g['elevator'] == true ? '있음' : '없음'}',
                  if (g['entry_steps'] != null) '입구 계단 ${g['entry_steps']}개',
                  if (g['resting_seats'] != null)
                    '쉬는 의자 ${g['resting_seats'] == true ? '있음' : '없음'}',
                  if ('${g['accessibility'] ?? ''}'.isNotEmpty)
                    '${g['accessibility']}',
                  if (g['elevator'] == null &&
                      g['entry_steps'] == null &&
                      g['resting_seats'] == null &&
                      '${g['accessibility'] ?? ''}'.isEmpty)
                    '확인된 이동 편의 정보가 없어요.',
                ].join(' · '),
              ),
            ],
            if (_guideError)
              TextButton(
                onPressed: () => _loadGuide(_detailGeneration),
                child: const Text('시설 안내 다시 불러오기'),
              ),
          ],
        ),
      ),
      for (final (i, path) in List<String>.from(g['image_paths'] ?? []).indexed)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PhotoViewer(
                  photos: [
                    for (final p in List<String>.from(g['image_paths']))
                      (file: null, path: p),
                  ],
                  initialIndex: i,
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: SocialPhoto(path: path),
              ),
            ),
          ),
        ),
      const SizedBox(height: 18),
      FacilityProgramPreview(place: r, onOpen: program, onList: programs),
      const SizedBox(height: 12),
      ActivityCard(
        child: ExpansionTile(
          maintainState: true,
          tilePadding: EdgeInsets.zero,
          title: Text('요일별 기관 프로그램 안내', style: petText(18)),
          subtitle: Text(
            '기존 주간 시간표 보기',
            style: petText(14, color: PetColors.secondary),
          ),
          onExpansionChanged: (v) => setState(() => _weekExpanded = v),
          children: _weekExpanded
              ? [WelfareProgramsSection(facilityName: r.name, telephone: phone)]
              : const [],
        ),
      ),
      const NeighborhoodHeading('이 시설 동네 모임', color: PetColors.blue),
      if (_upcomingMeetups == null)
        const ActivityCard(child: LinearProgressIndicator())
      else if (_upcomingMeetups!.isEmpty)
        const ActivityEmpty('예정된 모임이 없어요', message: '동네 모임에서 새 모임을 찾아보세요.')
      else
        ActivityCard(
          child: Column(
            children: [
              for (final m in _upcomingMeetups!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.event_outlined,
                    color: PetColors.green,
                  ),
                  title: Text('${m['title']}', style: petText(18)),
                  subtitle: Text(
                    _formatEventAt('${m['event_at']}'),
                    style: petText(15, color: PetColors.secondary),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenPost != null
                      ? widget.onOpenPost!('${m['id']}')
                      : Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PostDetailPage(postId: '${m['id']}'),
                          ),
                        ),
                ),
            ],
          ),
        ),
    ];
    final body = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: info,
      ),
    );
    return widget.showBackButton
        ? NeighborhoodScreen(
            title: '시설 정보',
            tint: const Color(0xFFDCEFFA),
            onBack: widget.onClose,
            child: body,
          )
        : ColoredBox(color: PetColors.background, child: body);
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

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_dialog.dart';
import '../attendance/attendance_repository.dart';
import '../attendance/point_badge.dart';
import '../community/community_page.dart';
import '../facility/facility_search_page.dart';
import '../meetup/meetup_page.dart';
import '../activity/activity_hub_page.dart';
import '../activity/activity_repository.dart';
import '../activity/activity_detail_page.dart';
import '../facility/nearby_facilities_page.dart';
import '../pet/pet_preview_controller.dart';
import '../pet/pet_repository.dart';
import '../pet/pet_walk_service.dart';
import '../pet/pet_design.dart';

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../pet/pet_preview_pages.dart';
import 'home_tab.dart';
import 'retained_map_tab.dart';
import 'nearby_facilities.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    this.facilityPage,
    this.nearbyLoader,
    this.activityRepository,
    this.attendanceRepository,
    this.petController,
  });
  final Widget? facilityPage;
  final PetPreviewController? petController;
  final AttendanceRepository? attendanceRepository;
  final NearbyLoader? nearbyLoader;
  final ActivityRepository? activityRepository;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  late final _petPreview =
      widget.petController ?? PetPreviewController(repository: PetRepository());
  StreamSubscription<AuthState>? _petAuth;
  Timer? _petClock;
  final _homeRefresh = ValueNotifier<int>(0);
  final _homeNavigator = GlobalKey<NavigatorState>();
  Color _homeSurface = PetColors.background;
  late final _homeObserver = _HomeSurfaceObserver((route) {
    final color = route?.settings.name == 'pet'
        ? PetColors.sky
        : PetColors.background;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _homeSurface != color) {
        setState(() => _homeSurface = color);
      }
    });
  });
  late final _attendance = AttendanceController(
    repository: widget.attendanceRepository,
  );
  DateTime? _attendancePromptedFor;
  bool _attendanceOpen = false;
  VoidCallback? _pendingAttendanceSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _petPreview.addListener(_refreshPoints);
    unawaited(_petPreview.load());
    final owner = Supabase.instance.client.auth.currentUser?.id;
    _petAuth = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.session?.user.id != owner) unawaited(PetWalkService().stop());
    });
    _petClock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(_petPreview.load());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptAttendance());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _petPreview.removeListener(_refreshPoints);
    if (_pendingAttendanceSync != null) {
      _petPreview.removeListener(_pendingAttendanceSync!);
    }
    _attendance.dispose();
    _petClock?.cancel();
    _petAuth?.cancel();
    if (widget.petController == null) _petPreview.dispose();
    _homeRefresh.dispose();
    super.dispose();
  }

  // A new KST day may start while the app sits in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _promptAttendance();
      unawaited(_petPreview.load());
    }
  }

  /// Opens the attendance popup once per server day until the user stamps.
  /// Closing it records nothing, so the next app start asks again.
  Future<void> _promptAttendance() async {
    final status = await _attendance.refresh();
    if (!mounted ||
        status == null ||
        status.attendedToday ||
        _attendanceOpen ||
        _attendancePromptedFor == status.today) {
      return;
    }
    _attendancePromptedFor = status.today;
    _attendanceOpen = true;
    await showAttendanceDialog(context, _attendance);
    if (mounted) await _syncAttendancePet();
    _attendanceOpen = false;
  }

  // The wallet and pet share the existing attendance transaction. If the
  // calendar already paid today's points, pet_action grants only the once-daily
  // pet experience; it never pays the wallet twice.
  Future<void> _syncAttendancePet() async {
    if (_petPreview.busy) {
      // A background pet refresh may overlap the stamp. Queue one sync rather
      // than losing that day's growth reward or issuing a concurrent mutation.
      if (_pendingAttendanceSync == null) {
        _pendingAttendanceSync = () {
          if (_petPreview.busy) return;
          final listener = _pendingAttendanceSync;
          _pendingAttendanceSync = null;
          if (listener != null) _petPreview.removeListener(listener);
          if (mounted) unawaited(_syncAttendancePet());
        };
        _petPreview.addListener(_pendingAttendanceSync!);
      }
      return;
    }
    if (!_petPreview.isPreview &&
        _petPreview.ready &&
        _petPreview.adopted &&
        _attendance.status?.attendedToday == true &&
        !_petPreview.attendanceRewarded) {
      try {
        await _petPreview.run('attendance');
      } catch (_) {
        await _petPreview.load();
      }
    } else {
      await _petPreview.load();
    }
  }

  void _refreshPoints() {
    if (!_petPreview.isPreview && _petPreview.ready && !_petPreview.busy) {
      unawaited(_attendance.refresh());
    }
  }

  bool _activityVisited = false;
  final _activityNavigator = GlobalKey<NavigatorState>();

  void _openActivity(Widget page) {
    setState(() {
      _index = 2;
      _activityVisited = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _activityNavigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => page),
        );
      }
    });
  }

  Widget _buildPage() {
    switch (_index) {
      case 0:
        return const SizedBox.shrink();
      case 1:
        return const SizedBox.shrink();
      case 2:
        return const SizedBox.shrink();
      case 3:
        return const MeetupPage();
      default:
        return const CommunityPage();
    }
  }

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: '홈',
    ),
    NavigationDestination(
      icon: Icon(Icons.map_outlined),
      selectedIcon: Icon(Icons.map),
      label: '시설 찾기',
    ),
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: '활동',
    ),
    NavigationDestination(
      icon: Icon(Icons.event_outlined),
      selectedIcon: Icon(Icons.event),
      label: '동네 모임',
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: '커뮤니티',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AttendanceScope(
      controller: _attendance,
      child: PetNavigationScope(
        navigator: Navigator.of(context),
        child: _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: _index == 0 ? _homeSurface : AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RetainedMapTab(
          selected: _index == 1,
          mapBuilder: (_, active) =>
              widget.facilityPage ??
              Scaffold(
                appBar: AppBar(
                  title: const Text('시설 찾기'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              NearbyFacilitiesPage(loader: widget.nearbyLoader),
                        ),
                      ),
                      child: const Text('주변 시설'),
                    ),
                    const PointBadge(),
                    const SizedBox(width: 8),
                  ],
                ),
                body: FacilitySearchPage(
                  isActive: active,
                  showDetailBackButton: true,
                ),
              ),
          child: Stack(
            children: [
              if (_index != 0 && _index != 2) _buildPage(),
              Offstage(
                offstage: _index != 0,
                child: TickerMode(
                  enabled: _index == 0,
                  child: NavigatorPopHandler<Object?>(
                    enabled: _index == 0,
                    onPopWithResult: (_) {
                      if (_index == 0) _homeNavigator.currentState?.maybePop();
                    },
                    child: Navigator(
                      key: _homeNavigator,
                      observers: [_homeObserver],
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) {
                          // Always construct the home entry, even if another tab
                          // was selected before this navigator finished building.
                          return HomeTab(
                            activityRepository: widget.activityRepository,
                            refreshListenable: _homeRefresh,
                            petPreview: _petPreview,
                            onAttendanceChanged: _syncAttendancePet,
                            onOpenPet: () => _homeNavigator.currentState!.push(
                              MaterialPageRoute<void>(
                                settings: const RouteSettings(name: 'pet'),
                                builder: (_) => !_petPreview.ready
                                    ? PetConnectionPage(pet: _petPreview)
                                    : _petPreview.adopted
                                    ? PetHomePage(pet: _petPreview)
                                    : PetAdoptionPage(pet: _petPreview),
                              ),
                            ),
                            onOpenActivity: (section) => _openActivity(
                              ActivitySectionPage(
                                section: section,
                                repository: widget.activityRepository,
                              ),
                            ),
                            onOpenProgram: (id) => _openActivity(
                              ActivityDetailPage(
                                programId: id,
                                repository: widget.activityRepository,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (_activityVisited)
                Offstage(
                  offstage: _index != 2,
                  child: TickerMode(
                    enabled: _index == 2,
                    child: NavigatorPopHandler<Object?>(
                      enabled: _index == 2,
                      onPopWithResult: (_) {
                        final navigator = _activityNavigator.currentState;
                        if (_index == 2 && navigator != null) {
                          navigator.maybePop();
                        }
                      },
                      child: Navigator(
                        key: _activityNavigator,
                        onGenerateRoute: (_) => MaterialPageRoute<void>(
                          builder: (_) => ActivityHubPage(
                            repository: widget.activityRepository,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: ColoredBox(
        color: AppColors.background,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: NavigationBar(
              height: 82,
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() {
                if (i == 0 && _index != 0) _homeRefresh.value++;
                _index = i;
                if (i == 2) _activityVisited = true;
              }),
              labelPadding: EdgeInsets.zero,
              destinations: _destinations,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSurfaceObserver extends NavigatorObserver {
  _HomeSurfaceObserver(this.onRoute);
  final void Function(Route<dynamic>?) onRoute;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    onRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    onRoute(newRoute);
  }
}

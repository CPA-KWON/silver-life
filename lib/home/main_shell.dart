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
  });
  final Widget? facilityPage;
  final AttendanceRepository? attendanceRepository;
  final NearbyLoader? nearbyLoader;
  final ActivityRepository? activityRepository;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  late final _attendance = AttendanceController(
    repository: widget.attendanceRepository,
  );
  DateTime? _attendancePromptedFor;
  bool _attendanceOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _promptAttendance());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _attendance.dispose();
    super.dispose();
  }

  // A new KST day may start while the app sits in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _promptAttendance();
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
    _attendanceOpen = false;
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
        return HomeTab(
          activityRepository: widget.activityRepository,
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
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: _index == 0
          ? AppColors.gradientStart
          : AppColors.background,
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
              Offstage(offstage: _index == 2, child: _buildPage()),
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
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() {
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

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../community/community_page.dart';
import '../facility/facility_search_page.dart';
import '../meetup/meetup_page.dart';
import '../profile/profile_page.dart';
import 'home_tab.dart';
import 'nearby_facilities.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, this.facilityPage, this.nearbyLoader});
  final Widget? facilityPage;
  final NearbyLoader? nearbyLoader;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  Widget _buildPage() {
    switch (_index) {
      case 0:
        return HomeTab(
          nearbyLoader: widget.nearbyLoader,
          onNavigate: (int index) => setState(() => _index = index),
        );
      case 1:
        return widget.facilityPage ?? const FacilitySearchPage();
      case 2:
        return const MeetupPage();
      case 3:
        return const CommunityPage();
      default:
        return const ProfilePage();
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
      label: '시설찾기',
    ),
    NavigationDestination(
      icon: Icon(Icons.event_outlined),
      selectedIcon: Icon(Icons.event),
      label: '모임',
    ),
    NavigationDestination(
      icon: Icon(Icons.groups_outlined),
      selectedIcon: Icon(Icons.groups),
      label: '커뮤니티',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '내 정보',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: _buildPage()),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.navBorder)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: _destinations,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../community/community_page.dart';
import '../facility/facility_search_page.dart';
import '../meetup/meetup_page.dart';
import '../profile/profile_page.dart';
import 'home_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['홈', '시설찾기', '모임', '커뮤니티', '내 정보'];

  static const _pages = [
    HomeTab(),
    FacilitySearchPage(),
    MeetupPage(),
    CommunityPage(),
    ProfilePage(),
  ];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home), label: '홈'),
    NavigationDestination(icon: Icon(Icons.map_outlined), label: '시설찾기'),
    NavigationDestination(icon: Icon(Icons.event_outlined), label: '모임'),
    NavigationDestination(icon: Icon(Icons.groups_outlined), label: '커뮤니티'),
    NavigationDestination(icon: Icon(Icons.person_outline), label: '내 정보'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

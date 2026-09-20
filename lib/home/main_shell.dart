import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/community_page.dart';
import '../facility/facility_search_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _titles = ['홈', '시설찾기', '커뮤니티'];

  static const _pages = [
    _PlaceholderTab(message: '환영합니다, 실버라이프입니다.'),
    FacilitySearchPage(),
    CommunityPage(),
  ];

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home), label: '홈'),
    NavigationDestination(icon: Icon(Icons.map_outlined), label: '시설찾기'),
    NavigationDestination(icon: Icon(Icons.groups_outlined), label: '커뮤니티'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: _destinations,
      ),
    );
  }
}

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

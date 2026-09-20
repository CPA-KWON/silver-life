import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _tabs = [
    _Tab(label: '홈', icon: Icons.home, message: '환영합니다, 실버라이프입니다.'),
    _Tab(
      label: '시설찾기',
      icon: Icons.map_outlined,
      message: '주변 병원·약국·경로당·복지관을 찾아보세요.',
    ),
    _Tab(label: '커뮤니티', icon: Icons.groups_outlined, message: '이웃과 소식을 나눠보세요.'),
  ];

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_index];
    return Scaffold(
      appBar: AppBar(
        title: Text(tab.label),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tab.message,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}

class _Tab {
  const _Tab({required this.label, required this.icon, required this.message});

  final String label;
  final IconData icon;
  final String message;
}

import 'package:flutter/material.dart';

import 'account_settings_page.dart';
import 'my_post_list_page.dart';
import 'privacy_policy_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MenuTile(
          icon: Icons.manage_accounts_outlined,
          title: '회원정보 관리',
          subtitle: '닉네임, 거주 지역 수정 및 로그아웃',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.article_outlined,
          title: '내 게시글 관리',
          subtitle: '내가 쓴 커뮤니티 글 모아보기',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MyPostListPage(title: '내 게시글 관리', isMeetup: false),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.event_outlined,
          title: '내 모임 관리',
          subtitle: '내가 쓴 동네모임 글 모아보기',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MyPostListPage(title: '내 모임 관리', isMeetup: true),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _MenuTile(
          icon: Icons.privacy_tip_outlined,
          title: '개인정보 처리방침',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
          ),
        ),
      ],
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

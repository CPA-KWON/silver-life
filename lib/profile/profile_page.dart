import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_settings_page.dart';
import 'my_post_list_page.dart';
import 'privacy_policy_page.dart';
import '../app_theme.dart';
import '../ui/design_widgets.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    return await Supabase.instance.client
        .from('profiles')
        .select('nickname, region_sido, region_sigungu')
        .eq('id', userId)
        .single();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageTitle('내 정보'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              FutureBuilder<Map<String, dynamic>>(
                future: _profileFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) return const SizedBox.shrink();
                  if (!snapshot.hasData) return const _ProfileCardSkeleton();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: _ProfileCard(profile: snapshot.data!),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('내 활동', style: textTheme.titleMedium),
              ),
              SectionCard(
                child: Column(
                  children: [
                    _MenuRow(
                      icon: Icons.article_outlined,
                      iconColor: AppColors.primary,
                      badgeColor: AppColors.tint,
                      title: '내 게시글 관리',
                      subtitle: '내가 쓴 커뮤니티 글 모아보기',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyPostListPage(
                            title: '내 게시글 관리',
                            isMeetup: false,
                          ),
                        ),
                      ),
                    ),
                    _MenuRow(
                      icon: Icons.event_outlined,
                      iconColor: AppColors.mintText,
                      badgeColor: AppColors.mintTint,
                      title: '내 모임 관리',
                      subtitle: '내가 쓴 동네모임 글 모아보기',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MyPostListPage(
                            title: '내 모임 관리',
                            isMeetup: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('설정', style: textTheme.titleMedium),
              ),
              SectionCard(
                child: Column(
                  children: [
                    _MenuRow(
                      icon: Icons.manage_accounts_outlined,
                      iconColor: AppColors.blueText,
                      badgeColor: AppColors.blueTint,
                      title: '회원정보 관리',
                      subtitle: '닉네임, 거주 지역 수정 및 로그아웃',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccountSettingsPage(),
                          ),
                        );
                        if (!mounted) return;
                        setState(() => _profileFuture = _loadProfile());
                      },
                    ),
                    _MenuRow(
                      icon: Icons.privacy_tip_outlined,
                      iconColor: AppColors.scheduleText,
                      badgeColor: AppColors.neutralTint,
                      title: '개인정보 처리방침',
                      subtitle: '언제든 확인할 수 있어요',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});

  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final nickname = (profile['nickname'] as String?) ?? '';
    final region = [
      profile['region_sido'],
      profile['region_sigungu'],
    ].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    final initial = nickname.isEmpty
        ? ''
        : String.fromCharCode(nickname.runes.first);

    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.tint,
              shape: BoxShape.circle,
            ),
            child: Text(
              initial,
              style: textTheme.titleLarge?.copyWith(
                fontSize: 22,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: textTheme.titleLarge?.copyWith(fontSize: 18),
                ),
                if (region.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(child: Text(region, style: textTheme.bodyMedium)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCardSkeleton extends StatelessWidget {
  const _ProfileCardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.neutralTint,
        borderRadius: BorderRadius.circular(6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SectionCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.neutralTint,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(120, 18), const SizedBox(height: 8), bar(80, 14)],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.iconColor,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              IconBadge(
                icon: icon,
                size: 40,
                color: iconColor,
                background: badgeColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall),
                    Text(subtitle, style: textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

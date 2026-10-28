import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../activity/activity_repository.dart';
import '../activity/activity_hub_page.dart';
import '../activity/activity_agency_page.dart';
import '../attendance/attendance_controller.dart';
import '../facility/nearby_facilities_page.dart';
import 'account_settings_page.dart';
import 'institution_access_page.dart';
import '../activity/saved_programs_page.dart';
import 'my_post_list_page.dart';
import 'privacy_policy_page.dart';
import 'extra_settings_pages.dart';
import 'sign_out.dart';
import '../meetup/my_meetups_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.activityRepository});
  final ActivityRepository? activityRepository;
  @override
  State<ProfilePage> createState() => _ProfileState();
}

class _ProfileState extends State<ProfilePage> {
  late Future<Map<String, dynamic>> data = load();
  late Future<ActivityData> agency =
      (widget.activityRepository ?? ActivityRepository()).home();
  late Future<Map<String, dynamic>?> access = loadAccess();
  Future<Map<String, dynamic>?> loadAccess() async {
    try {
      final c = Supabase.instance.client;
      return await c
          .from('institution_access_requests')
          .select('status')
          .eq('user_id', c.auth.currentUser!.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> load() async {
    final c = Supabase.instance.client,
        u = c.auth.currentUser!.id,
        p = await c.from('profiles').select().eq('id', u).single();
    try {
      final n = await Future.wait([
        c
            .from('posts')
            .count(CountOption.exact)
            .eq('author_id', u)
            .neq('category', '동네모임'),
        c
            .from('posts')
            .count(CountOption.exact)
            .eq('author_id', u)
            .eq('category', '동네모임'),
        c.from('favorites').count(CountOption.exact).eq('user_id', u),
      ]);
      p['stats'] = n;
    } catch (_) {
      p['stats'] = null;
    }
    return p;
  }

  Future<void> open(Widget w) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    if (mounted &&
        uid != null &&
        Supabase.instance.client.auth.currentUser?.id == uid) {
      setState(() {
        data = load();
        access = loadAccess();
        agency = (widget.activityRepository ?? ActivityRepository()).home();
      });
    }
  }

  Widget item(
    IconData icon,
    String title,
    VoidCallback action, {
    String? subtitle,
    Color color = PetColors.blue,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: color),
    ),
    title: Text(title, style: petText(18)),
    subtitle: subtitle == null
        ? null
        : Text(subtitle, style: petText(13, color: PetColors.secondary)),
    trailing: const Icon(Icons.chevron_right),
    onTap: action,
  );
  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '내 정보',
    tint: const Color(0xFFE2F0FB),
    child: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (c, s) => s.connectionState != ConnectionState.done
          ? const NeighborhoodLoading()
          : s.hasError
          ? ActivityEmpty(
              '내 정보를 불러오지 못했어요',
              action: '다시 시도',
              onAction: () => setState(() {
                data = load();
              }),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                NeighborhoodHero(
                  title: '${s.data!['nickname']} 님',
                  subtitle:
                      '${s.data!['region_sido']} · ${s.data!['region_sigungu']}',
                  color: PetColors.blue,
                  tags: [
                    TextButton(
                      onPressed: () => open(const AccountSettingsPage()),
                      child: const Text(
                        '회원정보 수정',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
                if (ActivityPetScope.maybeOf(c)?.adopted == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ActivityCard(
                      onTap: ActivityPetScope.openPetOf(c),
                      child: Row(
                        children: [
                          const Icon(Icons.pets, color: PetColors.blue),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${ActivityPetScope.maybeOf(c)!.name} · 나의 반려동물',
                              style: petText(18),
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                ActivityCard(
                  child: Wrap(
                    alignment: WrapAlignment.spaceAround,
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Column(
                          children: [
                            Text(
                              s.data!['stats'] == null
                                  ? '—'
                                  : '${s.data!['stats'][i]}',
                              style: petText(23),
                            ),
                            Text(
                              ['쓴 글', '만든 모임', '즐겨찾기'][i],
                              style: petText(12, color: PetColors.secondary),
                            ),
                          ],
                        ),
                      Column(
                        children: [
                          Text(
                            '${AttendanceScope.maybeOf(c)?.status?.balance ?? '—'}',
                            style: petText(23, color: PetColors.orange),
                          ),
                          Text(
                            '포인트',
                            style: petText(12, color: PetColors.secondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const NeighborhoodHeading('내 활동'),
                ActivityCard(
                  child: Column(
                    children: [
                      item(
                        Icons.explore_outlined,
                        '나의 활동',
                        () => open(
                          ActivitySectionPage(
                            section: ActivitySection.mine,
                            repository: widget.activityRepository,
                          ),
                        ),
                      ),
                      item(
                        Icons.article_outlined,
                        '내가 쓴 글·댓글',
                        () => open(
                          const MyPostListPage(
                            title: '내가 쓴 글·댓글',
                            isMeetup: false,
                          ),
                        ),
                        color: PetColors.purple,
                      ),
                      item(
                        Icons.groups_outlined,
                        '내가 만든 모임',
                        () => open(
                          const MyPostListPage(
                            title: '내가 만든 모임',
                            isMeetup: true,
                          ),
                        ),
                        color: PetColors.green,
                      ),
                      item(
                        Icons.groups_outlined,
                        '참여한 모임',
                        () => open(const MyMeetupsPage()),
                        color: PetColors.green,
                      ),
                      item(
                        Icons.favorite_border,
                        '관심 프로그램',
                        () => open(
                          SavedProgramsPage(
                            repository: widget.activityRepository,
                          ),
                        ),
                        color: PetColors.pink,
                      ),
                      item(
                        Icons.star_outline,
                        '즐겨찾는 시설',
                        () => open(const FavoriteFacilitiesPage()),
                        color: PetColors.orange,
                      ),
                    ],
                  ),
                ),
                const NeighborhoodHeading('설정'),
                ActivityCard(
                  child: Column(
                    children: [
                      item(
                        Icons.manage_accounts_outlined,
                        '회원정보 관리',
                        () => open(const AccountSettingsPage()),
                      ),
                      item(
                        Icons.notifications_none,
                        '알림·글씨 크기',
                        () => open(const ReadingSettingsPage()),
                      ),
                      item(
                        Icons.lock_outline,
                        '차단한 사용자',
                        () => open(const BlockedUsersPage()),
                      ),
                      item(
                        Icons.privacy_tip_outlined,
                        '이용약관·개인정보',
                        () => open(const PrivacyPolicyPage()),
                      ),
                    ],
                  ),
                ),
                FutureBuilder<ActivityData>(
                  future: agency,
                  builder: (c, a) {
                    if (a.hasError) {
                      return TextButton(
                        onPressed: () => setState(() {
                          agency =
                              (widget.activityRepository ??
                                      ActivityRepository())
                                  .home();
                        }),
                        child: const Text('기관 권한 확인 다시 시도'),
                      );
                    }
                    final org = activityRows(a.data?['organizations']);
                    return org.isEmpty
                        ? FutureBuilder<Map<String, dynamic>?>(
                            future: access,
                            builder: (c, r) {
                              final status = r.data?['status'];
                              return Padding(
                                padding: const EdgeInsets.only(top: 18),
                                child: ActivityCard(
                                  child: item(
                                    Icons.business_outlined,
                                    status == 'pending'
                                        ? '기관 인증 심사 중'
                                        : status == 'rejected'
                                        ? '기관 인증 반려 · 확인'
                                        : '기관 담당자 인증',
                                    () => open(const InstitutionAccessPage()),
                                    subtitle: '기관 등록·인증 심사 상태 확인',
                                  ),
                                ),
                              );
                            },
                          )
                        : Column(
                            children: [
                              const NeighborhoodHeading('기관 담당자'),
                              ActivityCard(
                                child: item(
                                  Icons.business_outlined,
                                  '기관 관리',
                                  () => open(
                                    ActivityAgencyPage(
                                      organizations: org,
                                      repository: widget.activityRepository,
                                    ),
                                  ),
                                  subtitle: '${org.first['name']}',
                                ),
                              ),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 18),
                ActivityCard(
                  child: item(
                    Icons.logout,
                    '로그아웃',
                    () => confirmAccountSignOut(c),
                    color: PetColors.secondary,
                  ),
                ),
                const SizedBox(height: 12),
                ActivityCard(
                  child: item(
                    Icons.person_remove_outlined,
                    '회원 탈퇴',
                    () => open(const DeleteAccountPage()),
                    color: Colors.red,
                  ),
                ),
              ],
            ),
    ),
  );
}

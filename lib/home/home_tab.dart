import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../activity/activity_repository.dart';
import '../activity/activity_hub_page.dart';
import '../activity/activity_detail_page.dart';
import '../activity/activity_widgets.dart';
import '../attendance/point_badge.dart';
import '../community/post_detail_page.dart';
import '../community/community_page.dart';
import '../core/meetup_category.dart';
import '../facility/facility_repository.dart';
import '../facility/naver_local_search.dart';
import '../facility/nearby_facilities_page.dart';
import '../meetup/meetup_page.dart';
import '../notices/notice_repository.dart';
import '../notices/notice_pages.dart';
import '../pet/pet_preview_controller.dart';
import '../pet/pet_design.dart';
import '../pet/pet_preview_pages.dart';
import '../profile/profile_page.dart';

typedef HomeData = ({
  String nickname,
  ActivityData? activity,
  List<FacilityResult>? favorites,
  List<ActivityData>? meetups,
  List<ActivityData>? news,
  List<NoticeData>? notices,
});

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    this.activityRepository,
    this.onOpenActivity,
    this.onOpenProgram,
    this.petPreview,
    this.onOpenPet,
    this.refreshListenable,
    this.noticeRepository,
  });
  final ActivityRepository? activityRepository;
  final NoticeRepository? noticeRepository;
  final PetPreviewController? petPreview;
  final VoidCallback? onOpenPet;
  final Listenable? refreshListenable;
  final ValueChanged<ActivitySection>? onOpenActivity;
  final ValueChanged<String>? onOpenProgram;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final repo = widget.activityRepository ?? ActivityRepository();
  late final notices = widget.noticeRepository ?? NoticeRepository();
  late Future<HomeData> future = load();
  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(reload);
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(reload);
    super.dispose();
  }

  Future<HomeData> load() async {
    final client = Supabase.instance.client;
    final profile = await client
        .from('profiles')
        .select('nickname, region_sido, region_sigungu')
        .eq('id', client.auth.currentUser!.id)
        .single();
    final favorites = loadFavoriteFacilities(limit: 3)
        .then<List<FacilityResult>?>((v) => v, onError: (_) => null);
    final activity = repo.home().then<ActivityData?>(
      (v) => v,
      onError: (_) => null,
    );
    final news = loadNews(profile)
        .then<List<ActivityData>?>((v) => v, onError: (_) => null);
    final meetups = loadMeetups(profile)
        .then<List<ActivityData>?>((v) => v, onError: (_) => null);
    final official = notices.feed().then<List<NoticeData>?>(
      (v) => v,
      onError: (_) => null,
    );
    return (
      nickname: profile['nickname'] as String,
      activity: await activity,
      favorites: await favorites,
      meetups: await meetups,
      news: await news,
      notices: await official,
    );
  }

  Future<List<ActivityData>> loadMeetups(Map<String, dynamic> profile) async {
    // Same facility-region filter as the existing meetup list. Public listings
    // have no participation status: do not label them as the user's enrolments.
    var query = Supabase.instance.client
        .from('posts')
        .select(
          'id, title, event_at, facilities!inner(name, region_sido, region_sigungu)',
        )
        .eq('category', kMeetupCategory)
        .eq('facilities.region_sido', profile['region_sido'])
        .gte('event_at', DateTime.now().toUtc().toIso8601String());
    final district = profile['region_sigungu'];
    if (district != null && district != '') {
      query = query.eq('facilities.region_sigungu', district);
    }
    return List<ActivityData>.from(await query.order('event_at').limit(2));
  }

  Future<List<ActivityData>> loadNews(Map<String, dynamic> profile) async {
    // Reuse CommunityPage's public-profile relation and region/RLS filters.
    var query = Supabase.instance.client
        .from('posts')
        .select(
          'id, title, category, created_at, profiles!inner(nickname, region_sido, region_sigungu)',
        )
        .neq('category', kMeetupCategory)
        .eq('profiles.region_sido', profile['region_sido']);
    final district = profile['region_sigungu'];
    if (district != null && district != '') {
      query = query.eq('profiles.region_sigungu', district);
    }
    return List<ActivityData>.from(
      await query.order('created_at', ascending: false).limit(2),
    );
  }

  Future<void> reload() async {
    if (!mounted) return;
    final next = load();
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {
      /* Builder has retry. */
    }
  }

  Future<void> open(Widget page) async {
    final user = Supabase.instance.client.auth.currentUser?.id;
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => page));
    if (mounted &&
        user != null &&
        Supabase.instance.client.auth.currentUser?.id == user) {
      await reload();
    }
  }

  void section(ActivitySection value) {
    if (widget.onOpenActivity != null) {
      widget.onOpenActivity!(value);
    } else {
      open(ActivitySectionPage(section: value, repository: repo));
    }
  }

  void program(String id) {
    if (widget.onOpenProgram != null) {
      widget.onOpenProgram!(id);
    } else {
      open(ActivityDetailPage(programId: id, repository: repo));
    }
  }

  DateTime? date(dynamic v) => DateTime.tryParse('$v')?.toLocal();
  String when(dynamic v) {
    final d = date(v);
    return d == null
        ? '일정 확인'
        : '${d.month}월 ${d.day}일 (${['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1]}) ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget title(String label, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(child: Text(label, style: petText(22))),
        ?trailing,
      ],
    ),
  );
  Widget newsHeading(String label, String action, VoidCallback onTap) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(label, style: petText(18)),
      TextButton(onPressed: onTap, child: Text(action)),
    ],
  );
  Widget newsEmpty(String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      label,
      style: petText(17, color: PetColors.secondary, weight: FontWeight.w500),
    ),
  );
  Widget newsRow({
    required String label,
    required String source,
    required bool official,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: official
                  ? const Color(0xFFFFF5E7)
                  : const Color(0xFFEAF4FB),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              official ? Icons.campaign_outlined : Icons.forum_outlined,
              color: official ? PetColors.orange : PetColors.blue,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: petText(20)),
                const SizedBox(height: 5),
                Text(
                  source,
                  style: petText(
                    16,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget header(String nickname) => Padding(
    padding: const EdgeInsets.only(left: 4, right: 4, top: 10, bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('안녕하세요, $nickname님', style: petText(26)),
              const SizedBox(height: 6),
              Text(
                '오늘도 동네에서 즐거운 하루 보내세요',
                style: petText(
                  17,
                  color: PetColors.secondary,
                  weight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          button: true,
          child: InkWell(
            onTap: () => open(ProfilePage(activityRepository: repo)),
            borderRadius: BorderRadius.circular(32),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD4E5F1),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      size: 32,
                      color: PetColors.blue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('내 정보', style: petText(15)),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  Widget eventRow({
    required String label,
    required String subtitle,
    required VoidCallback onTap,
    bool confirmed = false,
    IconData icon = Icons.calendar_today_outlined,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFE9F4FC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: PetColors.blue, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: petText(20)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: petText(
                    16,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
                if (confirmed)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: PetPill(
                      '참여 예정',
                      color: PetColors.mint,
                      ink: PetColors.green,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget emptyMeetups() => PetCard(
    padding: 20,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('아직 예정된 동네 모임이 없어요', style: petText(19)),
        const SizedBox(height: 6),
        Text(
          '가까운 모임에서 이웃을 만나보세요',
          style: petText(
            16,
            color: PetColors.secondary,
            weight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 14),
        PetPrimary(
          '동네 모임 둘러보기',
          light: true,
          onTap: () => open(const MeetupPage()),
        ),
      ],
    ),
  );
  Widget dashboard(HomeData home) {
    final data = home.activity, now = DateTime.now();
    final missions = activityRows(data?['missions']);
    final upcoming =
        activityRows(data?['applications'])
            .where(
              (e) =>
                  e['program'] is Map &&
                  e['status'] == 'approved' &&
                  date(e['program']['starts_at'])?.isAfter(now) == true,
            )
            .toList()
          ..sort(
            (a, b) =>
                date(a['program']['starts_at'])!
                    .compareTo(date(b['program']['starts_at'])!),
          );
    final endWeek = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: 8 - now.weekday));
    final weekly = upcoming
        .where((e) => date(e['program']['starts_at'])!.isBefore(endWeek))
        .length;
    final recommendations = activityRows(data?['recommendations'])
        .where((p) => p['kind'] == 'activity')
        .take(2)
        .toList();
    final meetups = home.meetups
        ?.where((m) => date(m['event_at'])?.isAfter(now) == true)
        .take(2)
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header(home.nickname),
          if (widget.petPreview != null && widget.onOpenPet != null)
            PetPreviewEntry(
              pet: widget.petPreview!,
              onTap: widget.onOpenPet!,
              nickname: home.nickname,
            ),
          title('다가오는 모임'),
          if (meetups == null)
            ActivityInfo('동네 모임을 불러오지 못했어요.', onRetry: reload)
          else if (meetups.isEmpty)
            emptyMeetups()
          else
            PetCard(
              padding: 16,
              child: Column(
                children: [
                  for (var i = 0; i < meetups.length; i++) ...[
                    if (i > 0) const Divider(color: PetColors.line),
                    eventRow(
                      label: '${meetups[i]['title']}',
                      subtitle:
                          '${when(meetups[i]['event_at'])} · ${meetups[i]['facilities']?['name'] ?? '장소 확인'}',
                      onTap: () =>
                          open(PostDetailPage(postId: '${meetups[i]['id']}')),
                    ),
                  ],
                ],
              ),
            ),
          title('동네 소식'),
          PetCard(
            padding: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                newsHeading(
                  '기관 공지',
                  '공지 더 보기',
                  () => open(NoticeListPage(repository: notices)),
                ),
                if (home.notices == null)
                  ActivityInfo('기관 공지를 불러오지 못했어요.', onRetry: reload)
                else if (home.notices!.isEmpty)
                  newsEmpty('아직 등록된 기관 공지가 없어요.'),
                for (final n in home.notices?.take(2) ?? <NoticeData>[])
                  newsRow(
                    label: '${n['title']}',
                    source: '기관 공지 · ${n['org_name']}',
                    official: true,
                    onTap: () => open(
                      NoticeDetailPage(id: n['id'], repository: notices),
                    ),
                  ),
                const Divider(height: 28, color: PetColors.line),
                newsHeading(
                  '지역 커뮤니티',
                  '커뮤니티 더 보기',
                  () => open(const CommunityPage()),
                ),
                if (home.news == null)
                  ActivityInfo('커뮤니티 글을 불러오지 못했어요.', onRetry: reload)
                else if (home.news!.isEmpty)
                  newsEmpty('아직 우리 동네 커뮤니티 글이 없어요.'),
                for (final n in home.news ?? <ActivityData>[])
                  newsRow(
                    label: '${n['title']}',
                    source: '지역 커뮤니티 · ${n['category']}',
                    official: false,
                    onTap: () => open(PostDetailPage(postId: '${n['id']}')),
                  ),
              ],
            ),
          ),
          // Empty weeks occupy no dashboard block. A real summary is compact and
          // follows the pet card instead of pushing the card out of the first screen.
          if (missions.isNotEmpty || weekly > 0) ...[
            const SizedBox(height: 16),
            PetCard(
              padding: 16,
              child: InkWell(
                onTap: () => section(ActivitySection.mine),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('이번 주 활동 현황', style: petText(20)),
                    const SizedBox(height: 6),
                    Text(
                      missions.isEmpty
                          ? '이번 주 참여 예정 $weekly개'
                          : '미션 ${missions.where((m) => m['status'] == 'completed').length}/${missions.length}개 완료 · 예정 $weekly개',
                      style: petText(17, color: PetColors.secondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (upcoming.isNotEmpty) ...[
            title('참여 예정 프로그램'),
            PetCard(
              padding: 16,
              child: eventRow(
                label: '${upcoming.first['program']['title']}',
                subtitle:
                    '${when(upcoming.first['program']['starts_at'])} · ${upcoming.first['program']['place_name']}',
                confirmed: true,
                onTap: () => program(upcoming.first['program']['id']),
              ),
            ),
          ],
          if (data == null) ...[
            const SizedBox(height: 20),
            ActivityInfo('활동 현황을 불러오지 못했어요.', onRetry: reload),
          ] else if (data['preferences'] != null &&
              recommendations.isNotEmpty) ...[
            title(
              '맞춤 추천 활동',
              trailing: TextButton(
                onPressed: () => section(ActivitySection.find),
                child: const Text('더 보기'),
              ),
            ),
            for (final p in recommendations)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PetCard(
                  padding: 16,
                  child: eventRow(
                    label: '${p['title']}',
                    subtitle: '${when(p['starts_at'])} · ${p['place_name']}',
                    icon: Icons.explore_outlined,
                    onTap: () => program(p['id']),
                  ),
                ),
              ),
          ],
          if (home.favorites != null && home.favorites!.isNotEmpty) ...[
            title(
              '즐겨찾는 시설',
              trailing: TextButton(
                onPressed: () => open(const FavoriteFacilitiesPage()),
                child: const Text('더 보기'),
              ),
            ),
            PetCard(
              padding: 16,
              child: Column(
                children: [
                  for (final f in home.favorites!)
                    eventRow(
                      label: f.name,
                      subtitle: f.address,
                      icon: Icons.star_outline,
                      onTap: () async {
                        await openSavedFacility(context, f);
                        if (mounted) await reload();
                      },
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Existing functions remain reachable without filling the home with empty cards.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: () => section(ActivitySection.find),
                child: const Text('맞춤 활동 찾기'),
              ),
              if (home.favorites == null || home.favorites!.isEmpty)
                TextButton(
                  onPressed: () => open(const FavoriteFacilitiesPage()),
                  child: const Text('즐겨찾는 시설'),
                ),
              const PointBadge(),
            ],
          ),
          if (home.favorites == null)
            ActivityInfo('즐겨찾는 시설을 불러오지 못했어요.', onRetry: reload),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) => RefreshIndicator(
    onRefresh: reload,
    child: ColoredBox(
      color: PetColors.background,
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          FutureBuilder<HomeData>(
            future: future,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (s.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: ActivityInfo('홈 정보를 불러오지 못했어요.', onRetry: reload),
                );
              }
              return dashboard(s.data!);
            },
          ),
        ],
      ),
    ),
  );
}

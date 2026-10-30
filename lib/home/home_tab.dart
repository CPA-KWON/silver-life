import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../activity/activity_repository.dart';
import '../activity/activity_hub_page.dart';
import '../activity/activity_detail_page.dart';
import '../activity/activity_widgets.dart';
import '../activity/activity_design.dart' show ActivityButton;
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_dialog.dart';
import 'home_widgets.dart';
import '../community/post_detail_page.dart';
import '../community/community_page.dart';
import '../core/meetup_category.dart';
import '../core/neighborhood_region.dart';
import '../facility/nearby_facilities_page.dart';
import '../meetup/meetup_page.dart';
import '../meetup/my_meetups_page.dart';
import '../notices/notice_repository.dart';
import '../notices/notice_pages.dart';
import '../pet/pet_preview_controller.dart';
import '../pet/pet_design.dart';
import '../pet/pet_preview_pages.dart';
import '../profile/profile_page.dart';

typedef HomeData = ({
  String nickname,
  ActivityData? activity,
  List<ActivityData>? meetups,
  List<ActivityData>? news,
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
    this.onAttendanceChanged,
    this.regionResolver,
  });
  final ActivityRepository? activityRepository;
  final NeighborhoodRegionResolver? regionResolver;
  final Future<void> Function()? onAttendanceChanged;
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
  Future<HomeData>? _pendingLoad;
  DateTime? _loadedAt;
  late Future<HomeData> future = _fetch();
  Future<HomeData> _fetch() =>
      _pendingLoad ??= load().whenComplete(() => _pendingLoad = null);
  void _onTabReturn() {
    if (_loadedAt == null ||
        DateTime.now().difference(_loadedAt!) > const Duration(seconds: 30)) {
      reload();
    }
  }

  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(_onTabReturn);
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_onTabReturn);
    super.dispose();
  }

  Future<HomeData> load() async {
    final client = Supabase.instance.client;
    final regionFuture =
        (widget.regionResolver ?? NeighborhoodRegionResolver.shared).resolve();
    final profile = await client
        .from('profiles')
        .select('nickname, region_sido, region_sigungu')
        .eq('id', client.auth.currentUser!.id)
        .single()
        .timeout(const Duration(seconds: 10));
    final activity = repo
        .homeSummary()
        .timeout(const Duration(seconds: 20))
        .then<ActivityData?>((v) => v, onError: (_) => null);
    final region = await regionFuture;
    final browsingRegion = <String, dynamic>{
      'region_sido': region.sido,
      'region_sigungu': region.sigungu,
    };
    final news = loadNews(browsingRegion)
        .timeout(const Duration(seconds: 12))
        .then<List<ActivityData>?>((v) => v, onError: (_) => null);
    final meetups = loadMeetups(browsingRegion)
        .timeout(const Duration(seconds: 12))
        .then<List<ActivityData>?>((v) => v, onError: (_) => null);
    final result = (
      nickname: profile['nickname'] as String,
      activity: await activity,
      meetups: await meetups,
      news: await news,
    );
    _loadedAt = DateTime.now();
    return result;
  }

  Future<List<ActivityData>> loadMeetups(Map<String, dynamic> profile) async {
    // Meetups I joined come first (marked "참여 예정"), then the rest of my
    // district's upcoming meetups. Joined ones may be outside my district.
    final joined = await loadMyMeetups()
        .then(
          (rows) => [
            for (final m in rows.where(isUpcomingMeetup))
              <String, dynamic>{
                'id': m['id'],
                'title': m['title'],
                'event_at': m['event_at'],
                'facilities': {'name': m['facility_name']},
                'joined': true,
              },
          ],
        )
        .catchError((_) => <Map<String, dynamic>>[]);
    final joinedIds = {for (final m in joined) m['id']};
    // Same facility-region filter as the existing meetup list. Public listings
    // carry no participation status, so they are not labelled as joined.
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
    final nearby = List<ActivityData>.from(
      await query.order('event_at').limit(2 + joined.length),
    ).where((m) => !joinedIds.contains(m['id']));
    return [...joined, ...nearby];
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
    final next = _fetch();
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

  Future<void> attendanceCalendar() async {
    final controller = AttendanceScope.maybeOf(context);
    if (controller == null) return;
    await showAttendanceDialog(context, controller);
    if (mounted) await widget.onAttendanceChanged?.call();
  }

  Widget title(String label) => Padding(
    padding: const EdgeInsets.only(top: 26, bottom: 12, left: 4),
    child: Text(label, style: petText(22, weight: FontWeight.w800)),
  );

  Widget newsGroup({
    required String label,
    required String empty,
    required String failure,
    required List<ActivityData>? rows,
    required VoidCallback onList,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EDFF),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.chat_outlined,
              color: Color(0xFF7450E8),
              size: 26,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: petText(19, weight: FontWeight.w800)),
                if (rows != null && rows.isEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    empty,
                    style: petText(
                      15,
                      color: const Color(0xFF728698),
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Semantics(
            label: '$label 더 보기',
            container: true,
            button: true,
            onTap: onList,
            excludeSemantics: true,
            child: TextButton(
              key: const ValueKey('home-community-more'),
              onPressed: onList,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.only(left: 6),
                minimumSize: const Size(62, 56),
              ),
              child: Text('더 보기 ›', style: petText(15, color: PetColors.blue)),
            ),
          ),
        ],
      ),
      if (rows == null) ActivityInfo(failure, onRetry: reload),
      for (final n in rows?.take(2) ?? <ActivityData>[])
        InkWell(
          onTap: () => open(PostDetailPage(postId: n['id'])),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(63, 8, 0, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${n['title']}', style: petText(18)),
                const SizedBox(height: 3),
                Text(
                  '지역 커뮤니티 · ${n['category']}',
                  style: petText(
                    14,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
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
  Widget emptyMeetups() => HomeCard(
    padding: 18,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Center(
          child: SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9F4FC),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Center(child: HomeMeetupIcon()),
                  ),
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFCE42),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      size: 19,
                      color: Color(0xFFA16B00),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '아직 예정된 동네 모임이 없어요',
          textAlign: TextAlign.center,
          style: petText(19, weight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          '가까운 모임에서 이웃을 만나보세요',
          textAlign: TextAlign.center,
          style: petText(
            16,
            color: PetColors.secondary,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
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
    final meetups = home.meetups
        ?.where((m) => date(m['event_at'])?.isAfter(now) == true)
        .take(2)
        .toList();
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HomeHeader(
            nickname: home.nickname,
            onProfile: () => open(ProfilePage(activityRepository: repo)),
            onCalendar: attendanceCalendar,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = MediaQuery.textScalerOf(context).scale(1) > 1.4
                    ? 1
                    : 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in [
                      (
                        '프로그램 찾기',
                        Icons.search_rounded,
                        ActivitySection.programs,
                      ),
                      (
                        '나의 활동',
                        Icons.event_available_outlined,
                        ActivitySection.mine,
                      ),
                    ])
                      SizedBox(
                        width: columns == 1 ? width : (width - 10) / 2,
                        child: ActivityButton(
                          item.$1,
                          icon: item.$2,
                          light: true,
                          onTap: () => section(item.$3),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          HomeAttendanceCard(
            onCalendar: attendanceCalendar,
            onStamped: widget.onAttendanceChanged,
          ),
          if (widget.petPreview != null && widget.onOpenPet != null) ...[
            const SizedBox(height: 16),
            PetPreviewEntry(
              pet: widget.petPreview!,
              onTap: widget.onOpenPet!,
              nickname: home.nickname,
            ),
          ],
          title('다가오는 모임'),
          if (meetups == null)
            ActivityInfo('동네 모임을 불러오지 못했어요.', onRetry: reload)
          else if (meetups.isEmpty && upcoming.isEmpty)
            emptyMeetups()
          else
            HomeCard(
              padding: 16,
              child: Column(
                children: [
                  for (var i = 0; i < meetups.length; i++) ...[
                    if (i > 0) const Divider(color: PetColors.line),
                    eventRow(
                      label: '${meetups[i]['title']}',
                      subtitle:
                          '${when(meetups[i]['event_at'])} · ${meetups[i]['facilities']?['name'] ?? '장소 확인'}',
                      confirmed: meetups[i]['joined'] == true,
                      onTap: () =>
                          open(PostDetailPage(postId: '${meetups[i]['id']}')),
                    ),
                  ],
                  for (final e in upcoming.take(1)) ...[
                    if (meetups.isNotEmpty)
                      const Divider(color: PetColors.line),
                    eventRow(
                      label: '${e['program']['title']}',
                      subtitle:
                          '${when(e['program']['starts_at'])} · ${e['program']['place_name']}',
                      confirmed: true,
                      onTap: () => program(e['program']['id']),
                    ),
                  ],
                ],
              ),
            ),
          title('동네 소식'),
          MyInstitutionNoticeCard(repository: notices, refreshKey: _loadedAt),
          const SizedBox(height: 12),
          HomeCard(
            padding: 18,
            child: newsGroup(
              label: '지역 커뮤니티',
              empty: '아직 우리 동네 글이 없어요',
              failure: '커뮤니티 글을 불러오지 못했어요.',
              rows: home.news,
              onList: () => open(const CommunityPage()),
            ),
          ),
          title('더 둘러보기'),
          LayoutBuilder(
            builder: (context, b) {
              final large =
                  MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
                  b.maxWidth < 310;
              final width = large ? b.maxWidth : (b.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: HomeExploreTile(
                      title: '맞춤 활동 찾기',
                      subtitle: '나에게 맞는\n동네 프로그램 추천',
                      icon: Icons.auto_awesome_outlined,
                      colors: const [Color(0xFFE2F4EC), Color(0xFFF0F9F5)],
                      ink: const Color(0xFF2B9565),
                      onTap: () => section(ActivitySection.find),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: HomeExploreTile(
                      title: '즐겨찾는 시설',
                      subtitle: '자주 가는 곳을\n한곳에 모아보기',
                      icon: Icons.star_outline_rounded,
                      colors: const [Color(0xFFFFF2DA), Color(0xFFFFF7E9)],
                      ink: const Color(0xFFE4930B),
                      onTap: () => open(const FavoriteFacilitiesPage()),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Text(
            '포인트·출석은 화면 맨 위에서 확인할 수 있어요',
            textAlign: TextAlign.center,
            style: petText(
              14,
              color: const Color(0xFF728698),
              weight: FontWeight.w600,
            ),
          ),
          if (data == null) ...[
            const SizedBox(height: 16),
            ActivityInfo('활동 현황을 불러오지 못했어요.', onRetry: reload),
          ],
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
              if (!s.hasData && s.connectionState != ConnectionState.done) {
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

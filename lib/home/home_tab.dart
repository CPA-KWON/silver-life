import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../activity/activity_repository.dart';
import '../activity/activity_hub_page.dart';
import '../activity/activity_detail_page.dart';
import '../activity/activity_widgets.dart';
import '../facility/facility_repository.dart';
import '../facility/naver_local_search.dart';
import '../facility/nearby_facilities_page.dart';
import '../profile/profile_page.dart';
import '../ui/design_widgets.dart';

typedef HomeData = ({
  String nickname,
  ActivityData? activity,
  List<FacilityResult>? favorites,
});

class HomeTab extends StatefulWidget {
  const HomeTab({
    super.key,
    this.activityRepository,
    this.onOpenActivity,
    this.onOpenProgram,
  });
  final ActivityRepository? activityRepository;
  final ValueChanged<ActivitySection>? onOpenActivity;
  final ValueChanged<String>? onOpenProgram;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late final repo = widget.activityRepository ?? ActivityRepository();
  late Future<HomeData> future = load();
  Future<HomeData> load() async {
    final client = Supabase.instance.client;
    final profile = await client
        .from('profiles')
        .select('nickname')
        .eq('id', client.auth.currentUser!.id)
        .single();
    final favorites = loadFavoriteFacilities(limit: 3)
        .then<List<FacilityResult>?>((v) => v, onError: (_) => null);
    ActivityData? data;
    try {
      data = await repo.home();
    } catch (_) {
      /* Keep profile usable. */
    }
    return (
      nickname: profile['nickname'] as String,
      activity: data,
      favorites: await favorites,
    );
  }

  Future<void> reload() async {
    if (!mounted) return;
    final f = load();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {
      /* FutureBuilder provides retry. */
    }
  }

  Future<void> open(Widget page) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted &&
        userId != null &&
        Supabase.instance.client.auth.currentUser?.id == userId) {
      await reload();
    }
  }

  void section(ActivitySection section) {
    if (widget.onOpenActivity != null) {
      widget.onOpenActivity!(section);
      return;
    }
    open(ActivitySectionPage(section: section, repository: repo));
  }

  void program(String id) {
    if (widget.onOpenProgram != null) {
      widget.onOpenProgram!(id);
      return;
    }
    open(ActivityDetailPage(programId: id, repository: repo));
  }

  DateTime? date(dynamic value) => DateTime.tryParse('$value')?.toLocal();

  List<Widget> favoriteSection(List<FacilityResult>? favorites) => [
    SectionHeader(
      title: '즐겨찾는 시설',
      trailing: favorites == null || favorites.isEmpty
          ? null
          : TextButton(
              onPressed: () => open(const FavoriteFacilitiesPage()),
              child: const Text('더 보기'),
            ),
    ),
    if (favorites == null)
      ActivityInfo(
        '즐겨찾는 시설을 불러오지 못했어요.',
        color: AppColors.background,
        onRetry: reload,
      )
    else if (favorites.isEmpty)
      const ActivityInfo(
        '아직 즐겨찾는 시설이 없어요.\n시설 찾기에서 별 모양 버튼으로 저장할 수 있어요.',
        color: AppColors.background,
      )
    else
      for (final f in favorites)
        ActivityMenuLink(
          title: f.name,
          subtitle: f.address,
          icon: Icons.star_outline,
          color: AppColors.background,
          onTap: () async {
            await openSavedFacility(context, f);
            if (mounted) await reload();
          },
        ),
  ];

  Widget dashboard(
    String nickname,
    ActivityData? d,
    List<FacilityResult>? favorites,
  ) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final missions = activityRows(d?['missions']);
    final upcoming =
        activityRows(d?['applications'])
            .where(
              (e) =>
                  e['status'] == 'approved' &&
                  date(e['program']['starts_at'])?.isAfter(now) == true,
            )
            .toList()
          ..sort(
            (a, b) =>
                date(a['program']['starts_at'])!
                    .compareTo(date(b['program']['starts_at'])!),
          );
    final weekly = upcoming
        .where((e) => date(e['program']['starts_at'])!.isBefore(nextMonday))
        .length;
    final recommendations = activityRows(d?['recommendations'])
        .where((p) => p['kind'] == 'activity')
        .take(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.gradientStart,
                AppColors.gradientStart,
                d == null ? AppColors.gradientStart : AppColors.gradientEnd,
              ],
              stops: const [0, 0.4, 1],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$nickname님, 안녕하세요',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${now.month}월 ${now.day}일',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppColors.heroCircle,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: const StadiumBorder(),
                    ),
                    onPressed: () =>
                        open(ProfilePage(activityRepository: repo)),
                    icon: const Icon(Icons.person_outline),
                    label: const Text('내 정보'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (d != null)
                WeeklyActivitySummary(
                  completed: missions
                      .where((m) => m['status'] == 'completed')
                      .length,
                  total: missions.length,
                  upcoming: weekly,
                  onOpen: () => section(ActivitySection.mine),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...d == null
                  ? [ActivityInfo('활동 현황을 불러오지 못했어요.', onRetry: reload)]
                  : [
                      const SectionHeader(title: '가장 가까운 예정 활동'),
                      if (upcoming.isEmpty)
                        const ActivityInfo(
                          '아직 확정된 예정 활동이 없어요.',
                          color: AppColors.background,
                        )
                      else
                        ActivityProgramCard(
                          program: Map<String, dynamic>.from(
                            upcoming.first['program'],
                          ),
                          label: '참여 예정',
                          color: AppColors.background,
                          onTap: () => program(upcoming.first['program']['id']),
                        ),
                      const SizedBox(height: 16),
                      SectionHeader(
                        title: '맞춤 추천 활동',
                        trailing: TextButton(
                          onPressed: () => section(ActivitySection.find),
                          child: const Text('더 보기'),
                        ),
                      ),
                      if (d['preferences'] == null)
                        ActivityMenuLink(
                          title: '추천 조건 설정',
                          subtitle: '기준 장소와 관심 분야를 알려주세요',
                          icon: Icons.tune,
                          color: AppColors.background,
                          onTap: () => section(ActivitySection.find),
                        )
                      else if (recommendations.isEmpty)
                        const ActivityInfo(
                          '현재 조건에 맞는 활동이 없어요.',
                          color: AppColors.background,
                        )
                      else
                        for (final p in recommendations)
                          ActivityProgramCard(
                            program: p,
                            color: AppColors.background,
                            onTap: () => program(p['id']),
                          ),
                    ],
              const SizedBox(height: 16),
              ...favoriteSection(favorites),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: DecoratedBox(
      decoration: const BoxDecoration(color: AppColors.gradientEnd),
      child: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          FutureBuilder<HomeData>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: ActivityInfo('홈 정보를 불러오지 못했어요.', onRetry: reload),
                );
              }
              final data = snapshot.data!;
              return dashboard(data.nickname, data.activity, data.favorites);
            },
          ),
        ],
      ),
    ),
  );
}

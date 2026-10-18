import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../activity/activity_repository.dart';
import '../activity/activity_hub_page.dart';
import '../activity/activity_detail_page.dart';
import '../activity/activity_widgets.dart';
import '../profile/profile_page.dart';
import '../ui/design_widgets.dart';

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
  late Future<({String nickname, ActivityData? activity})> future = load();
  Future<({String nickname, ActivityData? activity})> load() async {
    final client = Supabase.instance.client;
    final profile = await client
        .from('profiles')
        .select('nickname')
        .eq('id', client.auth.currentUser!.id)
        .single();
    ActivityData? data;
    try {
      data = await repo.home();
    } catch (_) {
      /* Keep profile usable. */
    }
    return (nickname: profile['nickname'] as String, activity: data);
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

  List<Widget> summary(ActivityData d) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    final missions = activityRows(d['missions']);
    final upcoming =
        activityRows(d['applications'])
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
    final recommendations = activityRows(d['recommendations'])
        .where((p) => p['kind'] == 'activity')
        .take(2);
    return [
      SectionCard(
        header: const SectionHeader(title: '이번 주 활동 현황'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '예정 활동 $weekly개 · ${missions.isEmpty ? '미션 미생성' : '미션 ${missions.where((m) => m['status'] == 'completed').length}/${missions.length}개 완료'}',
            ),
            TextButton(
              onPressed: () => section(ActivitySection.mine),
              child: const Text('나의 활동 보기'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const SectionHeader(title: '가장 가까운 예정 활동'),
      if (upcoming.isEmpty)
        const ActivityInfo('아직 확정된 예정 활동이 없어요.')
      else
        ActivityProgramCard(
          program: Map<String, dynamic>.from(upcoming.first['program']),
          label: '참여 예정',
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
          onTap: () => section(ActivitySection.find),
        )
      else if (recommendations.isEmpty)
        const ActivityInfo('현재 조건에 맞는 활동이 없어요.')
      else
        for (final p in recommendations)
          ActivityProgramCard(program: p, onTap: () => program(p['id'])),
    ];
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${DateTime.now().month}월 ${DateTime.now().day}일',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => open(ProfilePage(activityRepository: repo)),
              icon: const Icon(Icons.person_outline),
              label: const Text('내 정보'),
            ),
          ],
        ),
        FutureBuilder<({String nickname, ActivityData? activity})>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ActivityInfo('홈 정보를 불러오지 못했어요.', onRetry: reload);
            }
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${data.nickname}님, 안녕하세요',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                if (data.activity == null)
                  ActivityInfo('활동 현황을 불러오지 못했어요.', onRetry: reload)
                else
                  ...summary(data.activity!),
              ],
            );
          },
        ),
      ],
    ),
  );
}

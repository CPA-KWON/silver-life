import 'package:flutter/material.dart';

import '../ui/design_widgets.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';
import 'activity_forms.dart';
import 'activity_detail_page.dart';
import 'activity_agency_page.dart';

class ActivityHubPage extends StatefulWidget {
  const ActivityHubPage({super.key, this.initialTab = 0, this.repository});
  final int initialTab;
  final ActivityRepository? repository;
  @override
  State<ActivityHubPage> createState() => _ActivityHubPageState();
}

class _ActivityHubPageState extends State<ActivityHubPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = repo.home();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final f = repo.home();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {
      /* FutureBuilder presents errors. */
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await reload();
  }

  Future<void> plan({bool rebuild = false}) async {
    if (busy) return;
    if (rebuild &&
        !await activityConfirm(
          context,
          '미션을 다시 고를까요?',
          '아직 신청하지 않은 미션만 다시 골라요. 신청·참여 이력은 유지돼요.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await repo.plan(rebuild: rebuild);
      await reload();
    } catch (e) {
      if (mounted) activityMessage(context, '미션을 만들지 못했어요. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget program(ActivityData p, {String? label}) => ActivityProgramCard(
    program: p,
    label: label,
    onTap: () => open(ActivityDetailPage(programId: p['id'], repository: repo)),
  );
  Widget list(List<Widget> children) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    ),
  );
  Widget missions(ActivityData d) {
    final m = activityRows(d['missions']);
    return list([
      const Text(
        '이번 주 나의 활동 미션',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      const Text('멀리 가는 것보다, 원하는 활동을 꾸준히 하는 것이 목표예요.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => open(
          ActivityPreferencesPage(initial: d['preferences'], repository: repo),
        ),
        icon: const Icon(Icons.tune),
        label: const Text('활동 설정'),
      ),
      if (d['preferences'] == null)
        const ActivityInfo('관심 분야와 기준 장소를 설정하면 내게 맞는 미션을 고를 수 있어요.')
      else ...[
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : () => plan(),
          child: Text(busy ? '미션 준비 중…' : '이번 주 미션 만들기'),
        ),
        if (m.isNotEmpty)
          TextButton(
            onPressed: busy ? null : () => plan(rebuild: true),
            child: const Text('신청 전 미션 다시 고르기'),
          ),
        if (m.isEmpty)
          const ActivityInfo('아직 이번 주 미션이 없어요. 조건에 맞는 실제 프로그램이 있어야 미션이 만들어져요.'),
        for (final mission in m)
          program(
            Map<String, dynamic>.from(mission['program']),
            label:
                '${mission['stage']}단계 · ${['익숙한 동네', '새로운 장소', '함께하는 활동'][(mission['stage'] as int) - 1]} · ${activityStatuses[mission['status']] ?? ''}',
          ),
        const SectionHeader(title: '내게 맞는 활동'),
        const Text('내 활동 설정을 만족하는 활동이에요. 유효한 기관 후원이 있으면 먼저 보여드려요.'),
        const SizedBox(height: 12),
        if (activityRows(d['recommendations']).isEmpty)
          const ActivityInfo('현재 설정에 맞는 모집 중 활동이 없어요.'),
        for (final p in activityRows(
          d['recommendations'],
        ).where((p) => !m.any((v) => v['program_id'] == p['id'])))
          program(p),
      ],
    ]);
  }

  Widget bank(ActivityData d) => list([
    const Text(
      '동네 경험 은행',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    const Text(
      '평생 쌓아온 경험을 이웃과 나눠요. 기관이 활동 완료를 확인하면 30일간 유료 기관 프로그램 참여비 50% 혜택을 받아요.',
    ),
    const SizedBox(height: 12),
    FilledButton.icon(
      onPressed: () => open(ActivityExperiencePage(repository: repo)),
      icon: const Icon(Icons.add),
      label: const Text('나눌 경험 등록'),
    ),
    const SectionHeader(title: '내가 나눌 경험'),
    if (activityRows(d['experiences']).isEmpty)
      const ActivityInfo('아직 등록한 경험이 없어요.'),
    for (final e in activityRows(d['experiences']))
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e['title']),
            subtitle: Text(
              '${e['category']} · ${e['active'] == true ? '참여 가능' : '쉬는 중'}',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () =>
                open(ActivityExperiencePage(existing: e, repository: repo)),
          ),
        ),
      ),
    const SectionHeader(title: '기관의 경험 나눔 모집'),
    const Text('전체 지역의 모집 목록이에요. 장소와 시간을 확인해주세요.'),
    const SizedBox(height: 12),
    if (!activityRows(d['programs']).any((p) => p['kind'] == 'experience'))
      const ActivityInfo('현재 모집 중인 경험 나눔이 없어요.'),
    for (final p in activityRows(
      d['programs'],
    ).where((p) => p['kind'] == 'experience'))
      program(p),
  ]);
  Widget applications(ActivityData d) => list([
    if (d['benefit_expires_at'] != null)
      ActivityInfo(
        '유료 기관 프로그램 50% 혜택\n${activityDate(d['benefit_expires_at'])}까지 새 신청에 적용돼요. 혜택은 중복 합산되지 않아요.',
      ),
    const SectionHeader(title: '내 신청·참여 이력'),
    if (activityRows(d['applications']).isEmpty)
      const ActivityInfo('아직 신청한 활동이 없어요.'),
    for (final e in activityRows(d['applications']))
      program(
        Map<String, dynamic>.from(e['program']),
        label:
            '${activityStatuses[e['status']]} · 확정 참여비 ${activityMoney(e['final_fee'])}',
      ),
  ]);
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    initialIndex: widget.initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('활동 미션 · 경험 은행'),
        bottom: const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: '활동 미션'),
            Tab(text: '경험 은행'),
            Tab(text: '전체 활동'),
            Tab(text: '내 신청'),
          ],
        ),
      ),
      body: FutureBuilder<ActivityData>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ActivityInfo(
                  '활동 서비스를 불러오지 못했어요. 신규 서비스가 아직 준비되지 않았거나 연결이 원활하지 않을 수 있어요.',
                  onRetry: reload,
                ),
              ],
            );
          }
          final d = s.data!;
          final orgs = activityRows(d['organizations']);
          return Column(
            children: [
              if (orgs.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => open(
                      ActivityAgencyPage(organizations: orgs, repository: repo),
                    ),
                    icon: const Icon(Icons.business_outlined),
                    label: const Text('기관 운영'),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    missions(d),
                    bank(d),
                    list([
                      const Text(
                        '전체 지역의 기관 프로그램이에요. 내 이동 가능 거리와 시간에 맞는지 확인해주세요.',
                      ),
                      const SizedBox(height: 12),
                      if (!activityRows(d['programs'])
                          .any((p) => p['kind'] == 'activity'))
                        const ActivityInfo('현재 모집 중인 프로그램이 없어요.'),
                      for (final p in activityRows(
                        d['programs'],
                      ).where((p) => p['kind'] == 'activity'))
                        program(p),
                    ]),
                    applications(d),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_theme.dart';
import '../ui/design_widgets.dart';
import '../attendance/point_badge.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';
import 'activity_forms.dart';
import 'activity_detail_page.dart';

enum ActivitySection {
  find,
  missions,
  mine,
  experience,
  programs,
  myExperiences,
  recruitment,
  support,
}

String activitySectionTitle(ActivitySection section) => switch (section) {
  ActivitySection.find => '맞춤 활동 찾기',
  ActivitySection.missions => '주간 미션',
  ActivitySection.mine => '나의 활동',
  ActivitySection.experience => '경험 나눔',
  ActivitySection.programs => '전체 프로그램',
  ActivitySection.myExperiences => '내 경험 관리',
  ActivitySection.recruitment => '기관 모집 탐색',
  ActivitySection.support => '경험 나눔 지원 현황',
};

/// A directory, not four sideways pages. Each destination has one purpose.
class ActivityHubPage extends StatelessWidget {
  const ActivityHubPage({super.key, this.repository});
  final ActivityRepository? repository;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('활동'),
      actions: const [PointBadge(), SizedBox(width: 8)],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final entry in const [
          (ActivitySection.find, Icons.search, '조건에 맞는 활동과 전체 프로그램'),
          (ActivitySection.missions, Icons.flag_outlined, '이번 주 3단계 미션과 진행 현황'),
          (ActivitySection.mine, Icons.event_available, '신청 상태·참여 이력·혜택'),
          (
            ActivitySection.experience,
            Icons.volunteer_activism,
            '내 경험 관리와 기관 모집 지원',
          ),
        ])
          ActivityMenuLink(
            title: activitySectionTitle(entry.$1),
            subtitle: entry.$3,
            icon: entry.$2,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ActivitySectionPage(
                  section: entry.$1,
                  repository: repository,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ActivityMenuLink extends StatelessWidget {
  const ActivityMenuLink({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.color = AppColors.surface,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SectionCard(
      color: color,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon: icon, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    ),
  );
}

class ActivitySectionPage extends StatefulWidget {
  const ActivitySectionPage({
    super.key,
    required this.section,
    this.repository,
    this.place,
  });
  final ActivitySection section;
  final ({String name, double lat, double lng})? place;
  final ActivityRepository? repository;
  @override
  State<ActivitySectionPage> createState() => _ActivitySectionPageState();
}

class _ActivitySectionPageState extends State<ActivitySectionPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future = repo.home();
  bool busy = false;
  String historyView = '신청 내역';

  Future<void> reload() async {
    if (!mounted) return;
    final f = repo.home();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {
      /* FutureBuilder shows a retry. */
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await reload();
  }

  void section(ActivitySection value) =>
      open(ActivitySectionPage(section: value, repository: repo));
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
    } catch (_) {
      if (mounted) activityMessage(context, '미션을 만들지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget program(ActivityData p, {String? label}) => ActivityProgramCard(
    program: p,
    label: label,
    onTap: () => open(ActivityDetailPage(programId: p['id'], repository: repo)),
  );
  Widget settings(ActivityData d) => OutlinedButton.icon(
    onPressed: () => open(
      ActivityPreferencesPage(initial: d['preferences'], repository: repo),
    ),
    icon: const Icon(Icons.tune),
    label: const Text('추천 조건 설정'),
  );
  List<Widget> find(ActivityData d) => [
    settings(d),
    const SizedBox(height: 12),
    if (d['preferences'] == null)
      const ActivityInfo('기준 장소와 관심 분야를 설정하면 맞춤 활동을 추천해드려요.')
    else ...[
      const SectionHeader(title: '맞춤 추천 결과'),
      if (activityRows(d['recommendations']).isEmpty)
        const ActivityInfo('현재 조건에 맞는 모집 중 활동이 없어요.'),
      for (final p in activityRows(d['recommendations'])) program(p),
    ],
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: () => section(ActivitySection.programs),
      child: const Text('전체 프로그램 탐색'),
    ),
  ];
  List<Widget> missions(ActivityData d) {
    final rows = activityRows(d['missions']);
    return [
      ActivityInfo(
        '이번 주 미션 ${rows.where((m) => m['status'] == 'completed').length}/${rows.length}개 완료',
      ),
      const SizedBox(height: 12),
      if (d['preferences'] == null) ...[
        const ActivityInfo('기준 장소와 관심 분야를 먼저 설정해주세요.'),
        settings(d),
      ] else ...[
        FilledButton(
          onPressed: busy ? null : () => plan(),
          child: Text(busy ? '미션 준비 중…' : '이번 주 미션 만들기'),
        ),
        if (rows.isNotEmpty)
          TextButton(
            onPressed: busy ? null : () => plan(rebuild: true),
            child: const Text('신청 전 미션 다시 고르기'),
          ),
        if (rows.isEmpty) const ActivityInfo('조건에 맞는 실제 프로그램이 있어야 미션이 만들어져요.'),
        for (final m in rows)
          program(
            Map<String, dynamic>.from(m['program']),
            label:
                '${m['stage']}단계 · ${['익숙한 동네', '새로운 장소', '함께하는 활동'][(m['stage'] as int) - 1]} · ${activityStatuses[m['status']] ?? ''}',
          ),
        TextButton(
          onPressed: () => section(ActivitySection.find),
          child: const Text('추천 조건 확인하기'),
        ),
      ],
    ];
  }

  List<Widget> experiences(ActivityData d) => [
    FilledButton.icon(
      onPressed: () => open(ActivityExperiencePage(repository: repo)),
      icon: const Icon(Icons.add),
      label: const Text('나눌 경험 등록'),
    ),
    const SizedBox(height: 12),
    const Text('내 경험은 나만 볼 수 있어요. 모집에 지원하면 해당 기관에 전달돼요.'),
    const SizedBox(height: 12),
    if (activityRows(d['experiences']).isEmpty)
      const ActivityInfo('아직 등록한 경험이 없어요.'),
    for (final e in activityRows(d['experiences']))
      ActivityMenuLink(
        title: e['title'],
        subtitle:
            '${e['category']} · ${e['active'] == true ? '참여 가능' : '쉬는 중'}',
        icon: Icons.edit_outlined,
        onTap: () =>
            open(ActivityExperiencePage(existing: e, repository: repo)),
      ),
  ];
  List<Widget> applications(ActivityData d, {bool supportOnly = false}) {
    final all = activityRows(d['applications']);
    final rows = all
        .where(
          (e) => supportOnly
              ? e['program']['kind'] == 'experience'
              : historyView == '참여 이력'
              ? e['status'] == 'completed'
              : e['status'] != 'completed',
        )
        .toList();
    return [
      if (!supportOnly)
        activitySelect('보기', historyView, [
          '신청 내역',
          '참여 이력',
          '혜택',
        ], (value) => setState(() => historyView = value)),
      if (!supportOnly && historyView == '혜택') ...[
        ActivityInfo(
          d['benefit_expires_at'] == null
              ? '현재 적용 중인 혜택이 없어요.'
              : '유료 기관 프로그램 참여비 50% 혜택\n${activityDate(d['benefit_expires_at'])}까지 새 신청에 적용돼요. 중복 합산되지 않아요.',
        ),
      ] else ...[
        if (rows.isEmpty)
          ActivityInfo(
            supportOnly
                ? '아직 지원한 경험 나눔이 없어요.'
                : historyView == '참여 이력'
                ? '아직 완료한 활동이 없어요.'
                : '아직 신청한 활동이 없어요.',
          ),
        for (final e in rows)
          program(
            Map<String, dynamic>.from(e['program']),
            label:
                '${activityStatuses[e['status']] ?? e['status']} · 확정 참여비 ${activityMoney(e['final_fee'])}',
          ),
      ],
    ];
  }

  List<Widget> content(ActivityData d) => switch (widget.section) {
    ActivitySection.find => find(d),
    ActivitySection.missions => missions(d),
    ActivitySection.mine => applications(d),
    ActivitySection.support => applications(d, supportOnly: true),
    ActivitySection.myExperiences => experiences(d),
    ActivitySection.experience => [
      for (final entry in const [
        (
          ActivitySection.myExperiences,
          Icons.edit_outlined,
          '나눌 경험 등록·수정과 참여 가능 상태',
        ),
        (ActivitySection.recruitment, Icons.search, '기관이 모집하는 경험 나눔 찾기'),
        (ActivitySection.support, Icons.assignment_outlined, '내 지원과 승인·완료 상태'),
      ])
        ActivityMenuLink(
          title: activitySectionTitle(entry.$1),
          subtitle: entry.$3,
          icon: entry.$2,
          onTap: () => section(entry.$1),
        ),
    ],
    ActivitySection.programs || ActivitySection.recruitment => [
      Text(
        widget.place == null
            ? '전체 지역의 모집 목록이에요. 장소와 시간을 확인해주세요.'
            : '${widget.place!.name}에서 모집 중인 프로그램이에요.',
      ),
      const SizedBox(height: 12),
      if (matchingPrograms(d).isEmpty)
        const ActivityInfo('현재 모집 중인 프로그램이 없어요.'),
      for (final p in matchingPrograms(d)) program(p),
    ],
  };
  List<ActivityData> matchingPrograms(ActivityData d) =>
      activityRows(d['programs']).where((p) {
        final place = widget.place;
        if (place != null) {
          final lat = p['lat'], lng = p['lng'];
          return p['place_name']?.toString().trim() == place.name.trim() &&
              lat is num &&
              lng is num &&
              Geolocator.distanceBetween(
                    place.lat,
                    place.lng,
                    lat.toDouble(),
                    lng.toDouble(),
                  ) <=
                  100;
        }
        return p['kind'] ==
            (widget.section == ActivitySection.programs
                ? 'activity'
                : 'experience');
      }).toList();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.place == null
            ? activitySectionTitle(widget.section)
            : '앱으로 신청하는 활동',
      ),
    ),
    body: FutureBuilder<ActivityData>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: snapshot.hasError
                ? [
                    ActivityInfo(
                      '활동 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.',
                      onRetry: reload,
                    ),
                  ]
                : content(snapshot.data!),
          ),
        );
      },
    ),
  );
}

import 'package:flutter/material.dart';

import '../ui/design_widgets.dart';
import '../notices/notice_pages.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';
import 'activity_design.dart';
import 'activity_forms.dart';
import 'activity_detail_page.dart';
import 'activity_hub_page.dart';

enum AgencySection {
  overview,
  programs,
  applications,
  experience,
  performance,
  experiencePrograms,
  experienceApplications,
}

String agencySectionTitle(AgencySection? section) => switch (section) {
  null => '기관 관리',
  AgencySection.overview => '운영 현황',
  AgencySection.programs => '프로그램 관리',
  AgencySection.applications => '신청자 관리',
  AgencySection.experience => '경험 나눔 관리',
  AgencySection.performance => '운영 성과',
  AgencySection.experiencePrograms => '경험 나눔 모집 관리',
  AgencySection.experienceApplications => '경험 나눔 지원자 관리',
};

class ActivityAgencyPage extends StatefulWidget {
  const ActivityAgencyPage({
    super.key,
    required this.organizations,
    this.repository,
    this.section,
  });
  final List<ActivityData> organizations;
  final ActivityRepository? repository;
  final AgencySection? section;
  @override
  State<ActivityAgencyPage> createState() => _ActivityAgencyPageState();
}

class _ActivityAgencyPageState extends State<ActivityAgencyPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future = repo.agency();
  bool busy = false;
  Future<void> reload() async {
    if (!mounted) return;
    final f = repo.agency();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await reload();
  }

  void section(AgencySection value) => open(
    ActivityAgencyPage(
      organizations: widget.organizations,
      repository: repo,
      section: value,
    ),
  );
  Future<void> run(String title, Future<void> Function() task) async {
    if (busy ||
        !await activityConfirm(context, title, '실제 신청과 활동 내용을 확인한 뒤 처리해주세요.')) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await task();
      await reload();
    } catch (_) {
      if (mounted) activityMessage(context, '처리하지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> reject(String id) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('반려 사유 입력'),
        content: TextField(
          controller: controller,
          maxLength: 300,
          decoration: const InputDecoration(hintText: '신청자에게 전달할 이유를 적어 주세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('다음'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    // Dispose after the dialog's reverse transition has removed its text field.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (confirmed != true || !mounted) return;
    if (reason.isEmpty) {
      await activityFailure(
        context,
        title: '반려 사유를 적어 주세요',
        message: '신청자가 이유를 알 수 있도록 간단히 적어 주세요.',
      );
      return;
    }
    await run('신청을 반려할까요?', () => repo.rejectWithReason(id, reason));
  }

  Widget menu(AgencySection value, IconData icon, String subtitle) =>
      ActivityMenuLink(
        title: agencySectionTitle(value),
        subtitle: subtitle,
        icon: icon,
        onTap: () => section(value),
      );
  List<Widget> programs(ActivityData d, {bool experience = false}) {
    final rows = activityRows(d['programs'])
        .where((p) => (p['kind'] == 'experience') == experience)
        .toList();
    return [
      FilledButton.icon(
        onPressed: () => open(
          ActivityProgramForm(
            organizations: widget.organizations,
            repository: repo,
            initialKind: experience ? 'experience' : 'activity',
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(experience ? '경험 나눔 모집 등록' : '프로그램 등록'),
      ),
      if (!experience)
        TextButton.icon(
          onPressed: () =>
              open(NoticeManagePage(organizations: widget.organizations)),
          icon: const Icon(Icons.campaign_outlined),
          label: const Text('기관 공지 관리'),
        ),
      const SizedBox(height: 12),
      if (rows.isEmpty) const ActivityInfo('등록한 프로그램이 없어요.'),
      for (final p in rows) ...[
        ActivityProgramCard(
          program: p,
          label: p['status'] == 'open' ? '모집 중' : '모집 마감',
          onTap: () =>
              open(ActivityDetailPage(programId: p['id'], repository: repo)),
        ),
        if (p['status'] == 'open')
          TextButton(
            onPressed: busy
                ? null
                : () => run('모집을 마감할까요?', () => repo.close(p['id'])),
            child: Text('${p['title']} 모집 마감'),
          ),
      ],
    ];
  }

  List<Widget> applications(ActivityData d, {bool experience = false}) {
    final rows = activityRows(d['applications'])
        .where((e) => (e['program']['kind'] == 'experience') == experience)
        .toList();
    return [
      if (rows.isEmpty) const ActivityInfo('아직 신청이 없어요.'),
      for (final e in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  e['program']['title'],
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('신청자: ${e['applicant']?['nickname'] ?? '닉네임 정보 없음'}'),
                Text(
                  '신청번호 ${e['id']}\n${activityStatuses[e['status']]} · ${activityMoney(e['final_fee'])}',
                ),
                if ((e['application_note'] as String? ?? '').isNotEmpty)
                  Text('기관에 하고 싶은 말: ${e['application_note']}'),
                if ((e['rejection_reason'] as String? ?? '').isNotEmpty)
                  Text('반려 사유: ${e['rejection_reason']}'),
                if (e['experience_snapshot'] != null) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('제출한 경험 보기'),
                    children: [
                      Text(
                        '${e['experience_snapshot']['title']}\n${e['experience_snapshot']['description']}\n가능 시간 ${e['experience_snapshot']['available_time']}\n선호 장소 ${e['experience_snapshot']['preferred_place']}\n활동 형태 ${e['experience_snapshot']['activity_type']}',
                      ),
                    ],
                  ),
                ],
                if (e['status'] == 'applied')
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => run(
                            '신청을 승인할까요?',
                            () => repo.manage(e['id'], 'approved'),
                          ),
                    child: const Text('신청 승인'),
                  ),
                if (['applied', 'approved'].contains(e['status']))
                  OutlinedButton(
                    onPressed: busy ? null : () => reject(e['id']),
                    child: const Text('신청 반려'),
                  ),
                if (e['status'] == 'approved')
                  FilledButton(
                    onPressed:
                        busy ||
                            DateTime.parse(e['program']['ends_at'])
                                .isAfter(DateTime.now())
                        ? null
                        : () => run(
                            '실제 활동 완료를 확인할까요?',
                            () => repo.manage(e['id'], 'completed'),
                          ),
                    child: const Text('실제 활동 완료 확인'),
                  ),
              ],
            ),
          ),
        ),
    ];
  }

  List<Widget> content(ActivityData d) {
    final programs = activityRows(d['programs']);
    final applications = activityRows(d['applications']);
    final m = d['metrics'] as Map;
    return switch (widget.section) {
      null => [
        for (final o in widget.organizations)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(o['name']),
          ),
        menu(
          AgencySection.overview,
          Icons.dashboard_outlined,
          '현재 운영과 승인 대기 요약',
        ),
        menu(AgencySection.programs, Icons.event_note, '일반 프로그램 등록·모집 마감'),
        menu(
          AgencySection.applications,
          Icons.people_outline,
          '일반 프로그램 신청 승인·반려·완료',
        ),
        menu(
          AgencySection.experience,
          Icons.volunteer_activism,
          '경험 나눔 모집과 제출된 경험 확인',
        ),
        menu(AgencySection.performance, Icons.bar_chart, '참여율·재참여율과 완료 실적'),
      ],
      AgencySection.overview => [
        ActivityInfo(
          '모집 중 ${programs.where((p) => p['status'] == 'open').length}개\n승인 대기 ${applications.where((e) => e['status'] == 'applied').length}건\n참여 예정 ${applications.where((e) => e['status'] == 'approved').length}건',
        ),
      ],
      AgencySection.performance => [
        ActivityInfo(
          '완료 ${m['completed']}건 · 참여자 ${m['participants']}명\n재참여자 ${m['repeat_participants']}명 · 참여 분야 ${m['categories']}개\n실제 참여율 ${m['completion_rate'] == null ? '집계 전' : '${m['completion_rate']}%'} · 재참여율 ${m['repeat_rate'] == null ? '집계 전' : '${m['repeat_rate']}%'}',
        ),
      ],
      AgencySection.programs => this.programs(d),
      AgencySection.applications => this.applications(d),
      AgencySection.experience => [
        menu(
          AgencySection.experiencePrograms,
          Icons.event_note,
          '경험 나눔 도우미 모집 등록·마감',
        ),
        menu(
          AgencySection.experienceApplications,
          Icons.people_outline,
          '지원자와 제출 경험·진행 상태 확인',
        ),
      ],
      AgencySection.experiencePrograms => this.programs(d, experience: true),
      AgencySection.experienceApplications => this.applications(
        d,
        experience: true,
      ),
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(agencySectionTitle(widget.section))),
    body: FutureBuilder<ActivityData>(
      future: future,
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: s.hasError
                ? [ActivityInfo('기관 정보를 불러오지 못했어요.', onRetry: reload)]
                : content(s.data!),
          ),
        );
      },
    ),
  );
}

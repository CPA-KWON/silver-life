import 'package:flutter/material.dart';

import '../ui/neighborhood_design.dart';
import '../notices/notice_pages.dart';
import 'activity_repository.dart';
import '../facility/facility_guide_page.dart';
import 'activity_forms.dart';
import 'activity_program_card.dart';

enum AgencySection {
  overview,
  programs,
  applications,
  experience,
  performance,
  experiencePrograms,
  experienceApplications,
}

String agencySectionTitle(AgencySection? s) => switch (s) {
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
  State<ActivityAgencyPage> createState() => _AgencyState();
}

class _AgencyState extends State<ActivityAgencyPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> data = repo.agency();
  String programFilter = '전체', stateFilter = 'applied', period = '이번 달';
  final selected = <String>{};
  bool busy = false;
  Future<void> reload() async {
    final f = repo.agency();
    setState(() {
      data = f;
      selected.clear();
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> open(Widget p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => p));
    if (mounted) await reload();
  }

  void go(AgencySection s) => open(
    ActivityAgencyPage(
      organizations: widget.organizations,
      repository: repo,
      section: s,
    ),
  );
  Future<void> edit([ActivityData? p]) => open(
    ActivityProgramForm(
      organizations: widget.organizations,
      repository: repo,
      initialKind: widget.section == AgencySection.experiencePrograms
          ? 'experience'
          : 'activity',
      existing: p,
    ),
  );
  Future<void> manage(List<String> ids, String action) async {
    if (ids.isEmpty || busy) return;
    String reason = '';
    if (action == 'rejected') {
      final r = await agencyRejectReason(context);
      if (r == null) return;
      reason = r;
      if (!mounted ||
          !await activityDialog(
            context,
            title: '신청을 반려할까요?',
            message: '신청자에게 아래 사유가 표시돼요.',
            action: '반려하기',
            rows: [('반려 사유', reason)],
          )) {
        return;
      }
    } else if (!await activityDialog(
      context,
      title: action == 'approved'
          ? '선택한 ${ids.length}명을 승인할까요?'
          : '실제 참여 완료를 확인할까요?',
      message: action == 'completed'
          ? '실제로 참여한 사람만 선택해 주세요. 기존 미션·보상에 반영돼요.'
          : '선택한 신청자에게 승인 상태가 표시돼요.',
      action: action == 'approved' ? '승인하기' : '참여 완료 확인',
      color: PetColors.green,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      if (ids.length == 1) {
        if (action == 'rejected') {
          await repo.rejectWithReason(ids.first, reason);
        } else {
          await repo.manage(ids.first, action);
        }
      } else {
        await repo.manageBatch(ids, action, reason: reason);
      }
      if (mounted) await reload();
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '처리하지 못했어요',
          message: '신청 상태·정원·활동 종료 시간을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget shortcut(String text, IconData icon, VoidCallback action) => SizedBox(
    width: (MediaQuery.sizeOf(context).width - 84) / 3,
    child: InkWell(
      onTap: action,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: PetColors.blue, size: 28),
            const SizedBox(height: 7),
            Text(text, style: petText(16), textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
  Widget metric(String label, String n, Color color, VoidCallback action) =>
      SizedBox(
        width: (MediaQuery.sizeOf(context).width - 48) / 2,
        child: ActivityCard(
          onTap: action,
          color: color,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: petText(16)),
              Text(n, style: petText(32, weight: FontWeight.w800)),
            ],
          ),
        ),
      );
  List<Widget> overview(ActivityData d) {
    final apps = activityRows(d['applications']),
        ps = activityRows(d['programs']);
    return [
      for (final o in widget.organizations)
        Text('${o['name']}', style: petText(15, color: PetColors.secondary)),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          metric(
            '신청 승인 대기',
            '${apps.where((a) => a['status'] == 'applied').length}',
            const Color(0xFFFFEDD0),
            () => go(AgencySection.applications),
          ),
          metric(
            '참여 확인 대기',
            '${apps.where((a) => a['status'] == 'approved').length}',
            const Color(0xFFD9F2E6),
            () => go(AgencySection.applications),
          ),
          metric(
            '경험 나눔 지원',
            '${apps.where((a) => a['program']['kind'] == 'experience' && a['status'] == 'applied').length}',
            const Color(0xFFFBE1ED),
            () => go(AgencySection.experience),
          ),
          metric(
            '운영 프로그램',
            '${ps.where((p) => p['status'] == 'open').length}',
            const Color(0xFFDDEEF9),
            () => go(AgencySection.programs),
          ),
        ],
      ),
      const NeighborhoodHeading('바로 가기'),
      ActivityCard(
        child: Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            shortcut(
              '프로그램',
              Icons.calendar_month,
              () => go(AgencySection.programs),
            ),
            shortcut(
              '신청자',
              Icons.people_outline,
              () => go(AgencySection.applications),
            ),
            shortcut(
              '경험 나눔',
              Icons.favorite_outline,
              () => go(AgencySection.experience),
            ),
            shortcut(
              '시설 안내',
              Icons.map_outlined,
              () =>
                  open(FacilityGuidePage(organizations: widget.organizations)),
            ),
            shortcut(
              '공지',
              Icons.campaign_outlined,
              () => open(NoticeManagePage(organizations: widget.organizations)),
            ),
            shortcut(
              '운영 성과',
              Icons.bar_chart,
              () => go(AgencySection.performance),
            ),
          ],
        ),
      ),
      const NeighborhoodHeading('이번 주 프로그램'),
      for (final p in ps.where((p) => p['status'] == 'open').take(3))
        programCard(p),
      if (ps.isEmpty)
        ActivityEmpty(
          '아직 등록한 프로그램이 없어요',
          action: '프로그램 등록',
          onAction: () => edit(),
        ),
    ];
  }

  Widget programCard(ActivityData p) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ActivityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PetPill('${p['category']}', fontSize: 12),
              PetPill(
                p['draft'] == true
                    ? '임시 저장'
                    : p['status'] == 'open'
                    ? '모집 중'
                    : '모집 마감',
                fontSize: 12,
                color: PetColors.mint,
                ink: PetColors.green,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('${p['title'] ?? ''}', style: petText(22)),
          Text(
            '${activityShortDate(p['starts_at'])} · ${p['place_name'] ?? ''}',
            style: petText(16, color: PetColors.secondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              Text(
                '${p['enrolled'] ?? 0}/${p['capacity'] ?? '—'}명 신청',
                style: petText(17),
              ),
              TextButton(onPressed: () => edit(p), child: const Text('수정')),
              TextButton(
                onPressed: () => go(AgencySection.applications),
                child: const Text('신청자 보기'),
              ),
              if (p['status'] == 'open')
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!await activityDialog(
                            context,
                            title: '모집을 마감할까요?',
                            message: '기존 신청 내역은 유지돼요.',
                            action: '모집 마감',
                          )) {
                            return;
                          }
                          try {
                            await repo.close(p['id']);
                            if (mounted) await reload();
                          } catch (_) {
                            if (mounted) {
                              await activityFailure(
                                context,
                                title: '모집을 마감하지 못했어요',
                              );
                            }
                          }
                        },
                  child: const Text('모집 마감'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  List<Widget> programs(ActivityData d) {
    final ps = activityRows(d['programs'])
        .where(
          (p) =>
              p['kind'] ==
              (widget.section == AgencySection.experiencePrograms
                  ? 'experience'
                  : 'activity'),
        )
        .toList();
    return [
      Wrap(
        spacing: 8,
        children: [
          for (final v in ['전체', '모집 중', '모집 마감'])
            ChoiceChip(
              label: Text(v),
              selected: programFilter == v,
              onSelected: (_) => setState(() => programFilter = v),
            ),
        ],
      ),
      const SizedBox(height: 12),
      for (final p in ps.where(
        (p) =>
            programFilter == '전체' ||
            p['status'] == (programFilter == '모집 중' ? 'open' : 'closed'),
      ))
        programCard(p),
      for (final draft in activityRows(d['drafts']))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ActivityCard(
            onTap: () => edit({
              ...Map<String, dynamic>.from(draft['data']),
              'org_id': draft['org_id'],
              'draft_id': draft['id'],
            }),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${draft['data']['title'] ?? ''}'.trim().isEmpty
                    ? '제목 없는 임시 저장'
                    : '${draft['data']['title']}',
              ),
              subtitle: const Text('임시 저장 · 눌러서 이어서 작성'),
              trailing: const Icon(Icons.edit_outlined),
            ),
          ),
        ),
      if (ps.isEmpty && activityRows(d['drafts']).isEmpty)
        const ActivityEmpty('등록한 프로그램이 없어요'),
      ActivityButton(
        widget.section == AgencySection.experiencePrograms
            ? '경험 나눔 모집 등록'
            : '새 프로그램 등록',
        icon: Icons.add,
        onTap: () => edit(),
      ),
    ];
  }

  List<Widget> applications(ActivityData d) {
    final all = activityRows(d['applications'])
        .where(
          (a) =>
              widget.section != AgencySection.experienceApplications ||
              a['program']['kind'] == 'experience',
        )
        .toList();
    final ps = activityRows(d['programs']);
    final rows = all
        .where(
          (a) =>
              (programFilter == '전체' || a['program_id'] == programFilter) &&
              a['status'] == stateFilter,
        )
        .toList();
    return [
      if (ps.isNotEmpty)
        DropdownButtonFormField<String>(
          initialValue: ps.any((p) => p['id'] == programFilter)
              ? programFilter
              : '전체',
          decoration: const InputDecoration(labelText: '프로그램'),
          items: [
            const DropdownMenuItem(value: '전체', child: Text('전체 프로그램')),
            for (final p in ps)
              DropdownMenuItem(
                value: '${p['id']}',
                child: Text('${p['title']}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() {
            programFilter = v!;
            selected.clear();
          }),
        ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in ['applied', 'approved', 'rejected', 'completed'])
            ChoiceChip(
              label: Text(activityStatuses[s]!),
              selected: stateFilter == s,
              onSelected: (_) => setState(() {
                stateFilter = s;
                selected.clear();
              }),
            ),
        ],
      ),
      if (rows.isEmpty)
        ActivityEmpty(
          '아직 신청자가 없어요',
          message: '등록한 프로그램을 기관 공지로 알려 보세요.',
          action: '공지로 알리기',
          onAction: () => open(NoticeForm(organizations: widget.organizations)),
        ),
      for (final a in rows)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ActivityCard(
            child: Row(
              children: [
                if (['applied', 'approved'].contains(stateFilter))
                  Checkbox(
                    value: selected.contains(a['id']),
                    onChanged: (v) => setState(() {
                      v == true
                          ? selected.add(a['id'])
                          : selected.remove(a['id']);
                    }),
                  ),
                NeighborAvatar(
                  '${a['applicant']?['nickname'] ?? '신청자'}',
                  radius: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => open(
                      AgencyApplicantPage(enrollment: a, repository: repo),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a['applicant']?['nickname'] ?? '신청자'}',
                          style: petText(19),
                        ),
                        Text(
                          '${a['program']['title']}',
                          style: petText(15, color: PetColors.secondary),
                        ),
                        Text(
                          activityStatuses[a['status']] ?? '확인 필요',
                          style: petText(14, color: PetColors.orange),
                        ),
                      ],
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      if (selected.isNotEmpty) ...[
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Text('${selected.length}명 선택', style: petText(17)),
            ActivityButton(
              '반려',
              light: true,
              onTap: busy ? null : () => manage(selected.toList(), 'rejected'),
            ),
            ActivityButton(
              stateFilter == 'applied' ? '승인하기' : '참여 완료 확인',
              color: PetColors.green,
              onTap: busy
                  ? null
                  : () => manage(
                      selected.toList(),
                      stateFilter == 'applied' ? 'approved' : 'completed',
                    ),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> performance(ActivityData d) {
    final all = activityRows(d['applications']);
    final now = DateTime.now();
    final since = period == '이번 주'
        ? DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1))
        : period == '이번 달'
        ? DateTime(now.year, now.month)
        : DateTime(2000);
    final eligible = all
        .where(
          (a) =>
              ['approved', 'completed'].contains(a['status']) &&
              (DateTime.tryParse('${a['program']['ends_at']}')?.isBefore(now) ??
                  false) &&
              (DateTime.tryParse('${a['program']['ends_at']}')
                      ?.isAfter(since) ??
                  false),
        )
        .toList();
    final done = eligible.where((a) => a['status'] == 'completed').toList();
    return [
      Wrap(
        spacing: 8,
        children: [
          for (final v in ['이번 주', '이번 달', '프로그램별'])
            ChoiceChip(
              label: Text(v),
              selected: period == v,
              onSelected: (_) => setState(() => period = v),
            ),
        ],
      ),
      const NeighborhoodHeading('참여 현황'),
      ActivityCard(
        child: Wrap(
          spacing: 30,
          runSpacing: 14,
          children: [
            Column(
              children: [
                Text(
                  '${done.length}명',
                  style: petText(30, color: PetColors.blue),
                ),
                const Text('참여 완료'),
              ],
            ),
            Column(
              children: [
                Text(
                  eligible.isEmpty
                      ? '집계 전'
                      : '${(done.length / eligible.length * 100).round()}%',
                  style: petText(30, color: PetColors.green),
                ),
                const Text('참여 완료율'),
              ],
            ),
          ],
        ),
      ),
      const NeighborhoodHeading('프로그램별 실적'),
      for (final p in activityRows(d['programs']))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${p['title']}', style: petText(18)),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value:
                      eligible.where((a) => a['program_id'] == p['id']).isEmpty
                      ? 0
                      : done.where((a) => a['program_id'] == p['id']).length /
                            eligible
                                .where((a) => a['program_id'] == p['id'])
                                .length,
                  color: PetColors.green,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(10),
                ),
                const SizedBox(height: 8),
                Text(
                  '참여 완료 ${done.where((a) => a['program_id'] == p['id']).length}명',
                  style: petText(15, color: PetColors.secondary),
                ),
              ],
            ),
          ),
        ),
      if (all.isEmpty) const ActivityEmpty('아직 집계할 참여 이력이 없어요'),
    ];
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: agencySectionTitle(widget.section),
    tint: const Color(0xFFD9E3F1),
    child: FutureBuilder<ActivityData>(
      future: data,
      builder: (c, s) => s.connectionState != ConnectionState.done
          ? const NeighborhoodLoading()
          : s.hasError
          ? ActivityEmpty('기관 정보를 불러오지 못했어요', action: '다시 시도', onAction: reload)
          : RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: switch (widget.section) {
                  null || AgencySection.overview => overview(s.data!),
                  AgencySection.programs ||
                  AgencySection.experiencePrograms => programs(s.data!),
                  AgencySection.applications ||
                  AgencySection.experienceApplications => applications(s.data!),
                  AgencySection.performance => performance(s.data!),
                  AgencySection.experience => [
                    ActivityCard(
                      child: Column(
                        children: [
                          ActivityButton(
                            '경험 나눔 모집 관리',
                            onTap: () => go(AgencySection.experiencePrograms),
                          ),
                          const SizedBox(height: 12),
                          ActivityButton(
                            '경험 나눔 지원자 관리',
                            onTap: () =>
                                go(AgencySection.experienceApplications),
                          ),
                        ],
                      ),
                    ),
                  ],
                },
              ),
            ),
    ),
  );
}

Future<String?> agencyRejectReason(BuildContext c) {
  String selected = '정원이 다 찼어요';
  return showModalBottomSheet<String>(
    context: c,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('반려 이유를 골라 주세요', style: petText(24)),
              const SizedBox(height: 14),
              for (final r in ['정원이 다 찼어요', '대상 조건이 맞지 않아요', '일정이 바뀌었어요'])
                ChoiceChip(
                  label: Text(r),
                  selected: selected == r,
                  onSelected: (_) => set(() => selected = r),
                ),
              TextField(
                decoration: const InputDecoration(labelText: '직접 적기'),
                maxLength: 1000,
                onChanged: (v) => set(() => selected = v),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('취소'),
              ),
              ActivityButton(
                '반려하기',
                color: Colors.red,
                onTap: selected.trim().length < 5
                    ? null
                    : () => Navigator.pop(c, selected.trim()),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class AgencyApplicantPage extends StatefulWidget {
  const AgencyApplicantPage({
    super.key,
    required this.enrollment,
    required this.repository,
  });
  final ActivityData enrollment;
  final ActivityRepository repository;
  @override
  State<AgencyApplicantPage> createState() => _ApplicantState();
}

class _ApplicantState extends State<AgencyApplicantPage> {
  bool busy = false;
  Future<void> act(String action) async {
    String? reason;
    if (action == 'rejected') {
      reason = await agencyRejectReason(context);
      if (reason == null) return;
      if (!mounted ||
          !await activityDialog(
            context,
            title: '신청을 반려할까요?',
            message: '신청자에게 아래 사유가 표시돼요.',
            action: '반려하기',
            rows: [('반려 사유', reason)],
          )) {
        return;
      }
    } else if (!await activityDialog(
      context,
      title: action == 'approved' ? '신청을 승인할까요?' : '실제 참여 완료를 확인할까요?',
      message: '신청자 화면과 기존 활동 이력에 반영돼요.',
      action: action == 'approved' ? '승인하기' : '참여 완료 확인',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      if (action == 'rejected') {
        await widget.repository.rejectWithReason(
          widget.enrollment['id'],
          reason!,
        );
      } else {
        await widget.repository.manage(widget.enrollment['id'], action);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '처리하지 못했어요',
          message: '현재 신청 상태와 활동 종료 시간을 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final a = widget.enrollment;
    return NeighborhoodScreen(
      title: '신청자 정보',
      tint: const Color(0xFFD9E3F1),
      bottom: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (['applied', 'approved'].contains(a['status']))
            ActivityButton(
              '반려',
              light: true,
              onTap: busy ? null : () => act('rejected'),
            ),
          if (a['status'] == 'applied')
            ActivityButton('승인하기', onTap: busy ? null : () => act('approved')),
          if (a['status'] == 'approved')
            ActivityButton(
              '실제 활동 완료 확인',
              color: PetColors.green,
              onTap: busy ? null : () => act('completed'),
            ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ActivityCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: NeighborAvatar(
                '${a['applicant']?['nickname'] ?? '신청자'}',
              ),
              title: Text(
                '${a['applicant']?['nickname'] ?? '신청자'}',
                style: petText(23),
              ),
              subtitle: Text('${a['program']['title']}'),
              trailing: PetPill(
                activityStatuses[a['status']] ?? '',
                fontSize: 12,
              ),
            ),
          ),
          const NeighborhoodHeading('제출한 내용'),
          ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('신청 메모', style: petText(16, color: PetColors.secondary)),
                Text(
                  '${a['application_note'] ?? '제출한 메모가 없어요'}',
                  style: petText(19),
                ),
                if (a['experience_snapshot'] != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '경험: ${a['experience_snapshot']['title']}',
                    style: petText(20),
                  ),
                  Text(
                    '${a['experience_snapshot']['description']}',
                    style: petText(18),
                  ),
                  Text(
                    '${a['experience_snapshot']['available_time'] ?? ''}',
                    style: petText(17),
                  ),
                ],
                if (a['rejection_reason'] != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '반려 사유: ${a['rejection_reason']}',
                    style: petText(18, color: Colors.red),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '연락처는 신청자가 제공한 경우에만 확인할 수 있어요.',
            style: petText(14, color: PetColors.secondary),
          ),
        ],
      ),
    );
  }
}

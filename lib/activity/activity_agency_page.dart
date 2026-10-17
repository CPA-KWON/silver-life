import 'package:flutter/material.dart';

import '../ui/design_widgets.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';
import 'activity_forms.dart';
import 'activity_detail_page.dart';

class ActivityAgencyPage extends StatefulWidget {
  const ActivityAgencyPage({
    super.key,
    required this.organizations,
    this.repository,
  });
  final List<ActivityData> organizations;
  final ActivityRepository? repository;
  @override
  State<ActivityAgencyPage> createState() => _ActivityAgencyPageState();
}

class _ActivityAgencyPageState extends State<ActivityAgencyPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    future = repo.agency();
  }

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
    } catch (e) {
      if (mounted) activityMessage(context, '처리하지 못했어요. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('기관 운영')),
    body: FutureBuilder<ActivityData>(
      future: future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [ActivityInfo('기관 정보를 불러오지 못했어요.', onRetry: reload)],
          );
        }
        final d = s.data!, m = d['metrics'] as Map;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ActivityInfo(
                '완료 ${m['completed']}건 · 참여자 ${m['participants']}명\n재참여자 ${m['repeat_participants']}명 · 참여 분야 ${m['categories']}개\n실제 참여율 ${m['completion_rate'] == null ? '집계 전' : '${m['completion_rate']}%'} · 재참여율 ${m['repeat_rate'] == null ? '집계 전' : '${m['repeat_rate']}%'}',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActivityProgramForm(
                        organizations: widget.organizations,
                        repository: repo,
                      ),
                    ),
                  );
                  if (mounted) await reload();
                },
                icon: const Icon(Icons.add),
                label: const Text('프로그램 등록'),
              ),
              const SectionHeader(title: '운영 프로그램'),
              if (activityRows(d['programs']).isEmpty)
                const ActivityInfo('등록한 프로그램이 없어요.'),
              for (final p in activityRows(d['programs'])) ...[
                ActivityProgramCard(
                  program: p,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ActivityDetailPage(
                          programId: p['id'],
                          repository: repo,
                        ),
                      ),
                    );
                    if (mounted) await reload();
                  },
                ),
                if (p['status'] == 'open')
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => run('모집을 마감할까요?', () => repo.close(p['id'])),
                    child: Text('${p['title']} 모집 마감'),
                  ),
              ],
              const SectionHeader(title: '신청 관리'),
              if (activityRows(d['applications']).isEmpty)
                const ActivityInfo('아직 신청이 없어요.'),
              for (final e in activityRows(d['applications']))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SectionCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          e['program']['title'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '신청번호 ${e['id']}\n${activityStatuses[e['status']]} · ${activityMoney(e['final_fee'])}',
                        ),
                        if (e['experience_snapshot'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '제출한 경험: ${e['experience_snapshot']['title']}\n${e['experience_snapshot']['description']}\n가능 시간 ${e['experience_snapshot']['available_time']}\n선호 장소 ${e['experience_snapshot']['preferred_place']}\n활동 형태 ${e['experience_snapshot']['activity_type']}',
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
                            onPressed: busy
                                ? null
                                : () => run(
                                    '신청을 반려할까요?',
                                    () => repo.manage(e['id'], 'rejected'),
                                  ),
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
            ],
          ),
        );
      },
    ),
  );
}

import 'package:flutter/material.dart';

import '../ui/design_widgets.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';
import 'activity_forms.dart';

class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({
    super.key,
    required this.programId,
    this.repository,
  });
  final String programId;
  final ActivityRepository? repository;
  @override
  State<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends State<ActivityDetailPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future;
  bool busy = false;
  String? experience;
  Future<ActivityData> load() async {
    final detail = await repo.detail(widget.programId);
    final home = await repo.home();
    return {...detail, 'experiences': home['experiences']};
  }

  @override
  void initState() {
    super.initState();
    future = load();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final f = load();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> action(ActivityData d, {required bool cancel}) async {
    if (busy) return;
    final p = d['program'] as Map;
    if (!await activityConfirm(
      context,
      cancel ? '신청을 취소할까요?' : '활동을 신청할까요?',
      cancel
          ? '신청이 취소되면 정원이 다른 분에게 배정될 수 있어요.'
          : '${p['title']}\n확정 전 예상 참여비 ${activityMoney(d['quote'])}\n금액은 신청 시 서버에서 다시 확인해요. 앱에서 결제하지 않아요.',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      if (cancel) {
        await repo.cancel(d['application']['id']);
      } else {
        await repo.apply(
          widget.programId,
          experienceId: p['kind'] == 'experience' ? experience : null,
        );
      }
      await reload();
      if (mounted) {
        activityMessage(
          context,
          cancel ? '신청을 취소했어요.' : '신청했어요. 내 신청에서 확정 금액과 승인 상태를 확인해주세요.',
        );
      }
    } catch (e) {
      if (mounted) activityMessage(context, '처리하지 못했어요. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('활동 안내')),
    body: FutureBuilder<ActivityData>(
      future: future,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (s.hasError) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [ActivityInfo('활동을 불러오지 못했어요.', onRetry: reload)],
          );
        }
        final d = s.data!,
            p = Map<String, dynamic>.from(d['program']),
            e = d['application'] as Map?;
        final support = p['kind'] == 'experience',
            applied =
                e != null &&
                ['applied', 'approved', 'completed'].contains(e['status']);
        final closed =
            p['status'] != 'open' ||
            !DateTime.parse(p['deadline']).isAfter(DateTime.now()) ||
            !DateTime.parse(p['starts_at']).isAfter(DateTime.now());
        final full = (p['enrolled'] as num) >= (p['capacity'] as num);
        final offers = activityRows(d['experiences'])
            .where((o) => o['active'] == true && o['category'] == p['category'])
            .toList();
        if (!offers.any((o) => o['id'] == experience)) experience = null;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SectionCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p['sponsored'] == true) const Text('기관 후원 · 우선 노출'),
                    Text(
                      p['title'],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text('${p['org_name']} · ${p['category']}'),
                    Text(
                      '${p['place_name']}\n${activityDate(p['starts_at'])} ~ ${activityDate(p['ends_at'])}\n모집 마감 ${activityDate(p['deadline'])}',
                    ),
                    const SizedBox(height: 12),
                    Text(p['description']),
                    const SizedBox(height: 12),
                    Text(
                      '정원 ${p['enrolled']}/${p['capacity']}명 · 난이도 ${p['difficulty']}\n참여 방식 ${p['participation']}\n이동수단 ${(p['transports'] as List).join(', ')}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '기본 참여비 ${activityMoney(p['fee'])}\n${applied ? '확정 참여비 ${activityMoney(e['final_fee'])}' : '예상 참여비 ${activityMoney(d['quote'])}'}',
                    ),
                    const Text('앱에서는 신청 금액만 확정해요. 실제 납부 방법은 기관 안내를 확인해주세요.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (applied) ...[
                ActivityInfo(
                  '${activityStatuses[e['status']]} · 확정 참여비 ${activityMoney(e['final_fee'])}',
                ),
                if (e['status'] != 'completed' &&
                    DateTime.parse(p['starts_at']).isAfter(DateTime.now()))
                  OutlinedButton(
                    onPressed: busy ? null : () => action(d, cancel: true),
                    child: const Text('신청 취소'),
                  ),
              ] else ...[
                if (support) ...[
                  const Text(
                    '이 분야의 경험을 선택해 지원해요. 활동 완료를 기관이 확인하면 30일간 50% 혜택을 받아요.',
                  ),
                  if (offers.isNotEmpty)
                    activitySelect<String>(
                      '지원할 경험',
                      experience ?? offers.first['id'],
                      [for (final o in offers) o['id'] as String],
                      (v) => setState(() => experience = v),
                      describe: (v) =>
                          offers.firstWhere((o) => o['id'] == v)['title'],
                    ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ActivityExperiencePage(
                            initialCategory: p['category'],
                            repository: repo,
                          ),
                        ),
                      );
                      if (mounted) await reload();
                    },
                    child: const Text('이 분야의 경험 등록'),
                  ),
                ],
                if (closed)
                  const ActivityInfo('모집이 마감된 활동이에요.')
                else if (full)
                  const ActivityInfo('정원이 모두 찼어요.'),
                FilledButton(
                  onPressed:
                      busy || closed || full || (support && offers.isEmpty)
                      ? null
                      : () {
                          if (support) experience ??= offers.first['id'];
                          action(d, cancel: false);
                        },
                  child: Text(
                    busy
                        ? '처리 중…'
                        : support
                        ? '경험 나눔 지원'
                        : '활동 신청',
                  ),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

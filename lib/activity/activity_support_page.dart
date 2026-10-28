import 'package:flutter/material.dart';

import '../pet/pet_design.dart';
import 'activity_design.dart';
import 'activity_repository.dart';
import 'activity_forms.dart';
import 'activity_detail_page.dart';
import 'activity_program_card.dart';

class ActivitySupportPage extends StatefulWidget {
  const ActivitySupportPage({
    super.key,
    required this.program,
    required this.repository,
  });
  final ActivityData program;
  final ActivityRepository repository;
  @override
  State<ActivitySupportPage> createState() => _SupportState();
}

class _SupportState extends State<ActivitySupportPage> {
  late Future<ActivityData> future = load();
  Future<ActivityData> load() async {
    final home = await widget.repository.home();
    final applicant = await widget.repository.applicant();
    return {...home, 'applicant': applicant};
  }

  final note = TextEditingController();
  ActivityData? selected;
  int step = 1;
  bool busy = false;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> register() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ActivityExperiencePage(
          repository: widget.repository,
          initialCategory: widget.program['category'],
        ),
      ),
    );
    if (mounted) {
      setState(() {
        future = load();
      });
    }
  }

  Future<void> submit() async {
    if (busy || selected == null) return;
    final accepted = await activityDialog(
      context,
      title: '이 내용으로 지원할까요?',
      message: '지원 후에도 기관 검토 전까지는 취소할 수 있어요.',
      action: '지원하기',
      secondary: '다시 볼게요',
      icon: Icons.send_outlined,
      rows: [
        ('모집', '${widget.program['title']}'),
        ('내 경험', '${selected!['title']}'),
      ],
    );
    if (!accepted || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.applyWithNote(
        widget.program['id'],
        experienceId: selected!['id'],
        note: note.text,
      );
      final d = await widget.repository.detail(widget.program['id']);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ActivityReceiptPage(
            program: widget.program,
            repository: widget.repository,
            support: true,
            application: d['application'],
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        await activityFailure(
          context,
          title: '지원 상태를 확인해 주세요',
          message: '지원 현황을 먼저 확인해 주세요. 모집이 마감됐거나, 기관에 남기는 말을 저장할 추가 서버 설정이 필요할 수 있어요. 작성한 내용은 이 화면에 유지돼요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ActivityScreen(
      title: '지원하기 · $step/2',
      processing: busy,
      tint: ActivityColors.pink,
      wallet: false,
      bottom: step == 1
          ? ActivityButton(
              '다음 · 제출 내용 확인',
              onTap: selected == null ? null : () => setState(() => step = 2),
            )
          : Row(
              children: [
                TextButton(
                  onPressed: busy ? null : () => setState(() => step = 1),
                  child: const Text('이전'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ActivityButton(
                    busy ? '지원하고 있어요' : '지원하기',
                    onTap: busy ? null : submit,
                  ),
                ),
              ],
            ),
      child: FutureBuilder<ActivityData>(
        future: future,
        builder: (context, s) {
          if (!s.hasData) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (s.hasError)
                  ActivityEmpty(
                    '내 경험을 불러오지 못했어요',
                    message: '잠시 후 다시 확인해 주세요',
                    action: '다시 시도',
                    onAction: () => setState(() {
                      future = load();
                    }),
                  )
                else
                  const ActivitySkeleton(),
              ],
            );
          }
          final experiences = activityRows(s.data!['experiences']);
          // Server accepts only the user's active experience in this category.
          final eligible = experiences
              .where(
                (e) =>
                    e['active'] == true &&
                    e['category'] == widget.program['category'],
              )
              .toList();
          if (selected != null) {
            selected = eligible
                .where((e) => e['id'] == selected!['id'])
                .firstOrNull;
          }
          final submitted = selected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: step == 1
                ? [
                    Text(
                      '어떤 경험으로 지원할까요?',
                      style: petText(20, color: PetColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    if (eligible.isEmpty)
                      Text(
                        '이 모집과 같은 분야의 참여 가능한 경험이 필요해요.',
                        style: petText(17, color: PetColors.secondary),
                      ),
                    for (final e in experiences) ...[
                      ActivityCard(
                        border: submitted?['id'] == e['id']
                            ? const BorderSide(
                                color: ActivityColors.blue,
                                width: 2,
                              )
                            : null,
                        color: submitted?['id'] == e['id']
                            ? const Color(0xFFEAF5FC)
                            : Colors.white,
                        onTap: eligible.contains(e)
                            ? () => setState(() => selected = e)
                            : null,
                        child: Row(
                          children: [
                            Icon(
                              submitted?['id'] == e['id']
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: eligible.contains(e)
                                  ? ActivityColors.blue
                                  : ActivityColors.muted,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${e['title']}', style: petText(21)),
                                  Text(
                                    '${e['category']} · ${e['available_time']} · ${e['active'] == true ? '참여 가능' : '쉬는 중'}',
                                    style: petText(
                                      16,
                                      color: PetColors.secondary,
                                    ),
                                  ),
                                  if (!eligible.contains(e))
                                    Text(
                                      e['active'] != true
                                          ? '참여 가능으로 바꾸면 지원할 수 있어요'
                                          : '이 모집과 분야가 달라요',
                                      style: petText(
                                        14,
                                        color: PetColors.orange,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ActivityButton(
                      '새 경험 등록하고 지원',
                      onTap: register,
                      light: true,
                      icon: Icons.add,
                    ),
                    const SizedBox(height: 18),
                    ActivityCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('기관에 하고 싶은 말 · 선택', style: petText(20)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: note,
                            maxLines: 4,
                            maxLength: 200,
                            decoration: const InputDecoration(
                              hintText: '가능한 시간이나 전달할 말을 적어 주세요',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]
                : [
                    Text(
                      '기관에 아래 내용이 전달돼요',
                      style: petText(18, color: PetColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    ActivityCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '지원하는 모집',
                            style: petText(15, color: PetColors.secondary),
                          ),
                          Text(
                            '${widget.program['title']}',
                            style: petText(22),
                          ),
                          Text(
                            '${widget.program['place_name']} · ${activityShortDate(widget.program['starts_at'])}',
                            style: petText(16, color: PetColors.secondary),
                          ),
                          const Divider(height: 28),
                          for (final row in [
                            (
                              '이름',
                              '${s.data!['applicant']?['nickname'] ?? '닉네임 확인 필요'}',
                            ),
                            ('내 경험', '${submitted?['title']}'),
                            ('경험 설명', '${submitted?['description']}'),
                            ('가능한 시간', '${submitted?['available_time']}'),
                            ('선호 장소', '${submitted?['preferred_place']}'),
                            ('활동 형태', '${submitted?['activity_type']}'),
                            (
                              '하고 싶은 말',
                              note.text.trim().isEmpty
                                  ? '추가로 남긴 말이 없어요'
                                  : note.text.trim(),
                            ),
                          ]) ...[
                            Text(
                              row.$1,
                              style: petText(15, color: PetColors.secondary),
                            ),
                            const SizedBox(height: 5),
                            Text(row.$2, style: petText(18)),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const ActivityPrivacyNotice(),
                  ],
          );
        },
      ),
    ),
  );
}

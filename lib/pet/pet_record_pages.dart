import '../core/points.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'pet_onboarding.dart';

import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_today_page.dart';
import 'pet_care_pages.dart';

class PetRecordsPage extends StatelessWidget {
  const PetRecordsPage({super.key, required this.pet});
  final PetPreviewController pet;
  String date(DateTime d) => '${d.month}/${d.day}';
  Future<void> rename(BuildContext c) async {
    final input = TextEditingController(text: pet.name);
    final name = await showDialog<String>(
      context: petModalContext(c),
      useRootNavigator: false,
      builder: (d) => AlertDialog(
        title: const Text('이름 바꾸기'),
        content: TextField(
          controller: input,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '이름 1~6자'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, input.text),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await pet.run('rename', {'name': name.trim()});
    } catch (e) {
      if (c.mounted) await showPetFailure(c, e);
    }
  }

  Future<void> tools(BuildContext c) => showModalBottomSheet<void>(
    context: c,
    useRootNavigator: false,
    builder: (d) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('디자인 미리보기 도구', style: petText(22)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < 3; i++)
                  TextButton(
                    onPressed: () {
                      pet.previewStage(i);
                      Navigator.pop(d);
                    },
                    child: Text(['아기', '성장기', '성체'][i]),
                  ),
              ],
            ),
            TextButton(
              onPressed: () async {
                await pet.run('preview_ready');
                if (d.mounted) Navigator.pop(d);
              },
              child: const Text('성장 준비 화면 확인'),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) {
      final many = pet.logs.length > 7;
      final adopted = pet.adoptedAt ?? pet.today;
      return PetScreen(
        colors: const [PetColors.background, PetColors.background],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetHeader('성장 기록', pet: pet),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFDFF0FB), Color(0xFFEEEDFF)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(
                children: [
                  SizedBox(width: 100, child: PetPhoto(pet: pet, height: 120)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pet.name}와 함께한 지',
                          style: petText(17, color: PetColors.blue),
                        ),
                        Text('${pet.daysTogether}일째', style: petText(29)),
                        Text(
                          '${adopted.year}년 ${adopted.month}월 ${adopted.day}일 입양',
                          style: petText(16, color: PetColors.secondary),
                        ),
                        TextButton(
                          onPressed: () => rename(c),
                          child: const Text('이름 바꾸기'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('성장 단계', style: petText(22)),
            const SizedBox(height: 12),
            PetCard(
              padding: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: 3,
                                color: i <= pet.stage
                                    ? PetColors.purple
                                    : PetColors.line,
                              ),
                            ),
                            child: Opacity(
                              opacity: i <= pet.stage ? 1 : .25,
                              child: PetPhoto(
                                pet: pet,
                                stage: i,
                                height: 82,
                                outfit: const {},
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(['아기', '성장기', '성체'][i], style: petText(18)),
                          Text(
                            pet.stageDates[i] != null
                                ? date(pet.stageDates[i]!)
                                : 'EXP ${i == 1 ? 200 : 500}',
                            style: petText(15, color: PetColors.secondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (many) ...[
              const SizedBox(height: 24),
              Text('지금까지 함께한 일', style: petText(22)),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final pair in [
                    ('feed', '먹이'),
                    ('walk', '산책'),
                    ('program', '프로그램'),
                    ('attendance', '출석'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: PetCard(
                          padding: 10,
                          child: Column(
                            children: [
                              Text('${pet.count(pair.$1)}', style: petText(27)),
                              Text(
                                pair.$2,
                                style: petText(14, color: PetColors.secondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('${pet.today.month}월 돌봄 달력', style: petText(22)),
              const SizedBox(height: 12),
              PetCard(
                child: LayoutBuilder(
                  builder: (c, b) => Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (
                        var day = 1;
                        day <=
                            DateTime(
                              pet.today.year,
                              pet.today.month + 1,
                              0,
                            ).day;
                        day++
                      )
                        Builder(
                          builder: (c) {
                            final n = pet.logs
                                .where(
                                  (l) =>
                                      l.date.year == pet.today.year &&
                                      l.date.month == pet.today.month &&
                                      l.date.day == day,
                                )
                                .length;
                            return Tooltip(
                              message: '$day일 · $n번 활동',
                              child: Container(
                                width: (b.maxWidth - 24) / 7,
                                height: 24,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  color: n == 0
                                      ? const Color(0xFFEEF2F6)
                                      : n > 2
                                      ? const Color(0xFF745FFF)
                                      : const Color(0xFFC9BEFF),
                                ),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(many ? '최근 기록' : '돌봄 · 활동 기록', style: petText(22)),
            const SizedBox(height: 12),
            PetCard(
              padding: 16,
              child: Column(
                children: [
                  if (pet.logs.isEmpty) Text('아직 기록이 없어요', style: petText(18)),
                  for (var i = 0; i < pet.logs.length; i++) ...[
                    if (i > 0) const Divider(height: 26),
                    Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            date(pet.logs[i].date),
                            style: petText(15, color: PetColors.secondary),
                          ),
                        ),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: pet.logs[i].kind == 'walk'
                                ? PetColors.mint
                                : PetColors.lavender,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _icon(pet.logs[i].kind),
                            color: pet.logs[i].kind == 'walk'
                                ? PetColors.green
                                : PetColors.purple,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(pet.logs[i].title, style: petText(17)),
                        ),
                        if (pet.logs[i].points > 0)
                          PetPill(
                            '+ ${pointAmount(pet.logs[i].points)} P',
                            color: PetColors.yellow,
                            ink: const Color(0xFF916100),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!many) ...[
              const SizedBox(height: 16),
              PetCard(
                color: const Color(0xFFF8FBFF),
                border: Border.all(color: PetColors.line, width: 2),
                child: Column(
                  children: [
                    Text(
                      '기록이 쌓이면 여기에 모아 보여드려요',
                      textAlign: TextAlign.center,
                      style: petText(19),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '오늘의 활동을 하면 ${pet.name}가 더 빨리 자라요',
                      textAlign: TextAlign.center,
                      style: petText(16, color: PetColors.secondary),
                    ),
                    const SizedBox(height: 16),
                    PetPrimary(
                      '오늘의 활동 하러 가기',
                      light: true,
                      onTap: () => Navigator.of(c).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PetTodayPage(pet: pet),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            TextButton(
              onPressed: () => petDialog(
                c,
                title: '반려동물 정보',
                message:
                    '${pet.name} · ${pet.isCat ? '고양이' : '강아지'} · ${pet.stageName}\n입양 후 ${pet.daysTogether}일째 함께하고 있어요.\n반려동물 종류가 늘어나도 기존 성장·포인트·옷과 기록은 유지돼요.',
              ),
              child: const Text('반려동물 정보'),
            ),
            if (pet.isPreview)
              TextButton(
                onPressed: () => tools(c),
                child: const Text('디자인 미리보기 도구'),
              ),
            if (kDebugMode && !pet.isPreview)
              TextButton(
                onPressed: () => Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PetAdoptionPage(
                      pet: PetPreviewController()..ready = true,
                    ),
                  ),
                ),
                child: const Text('확장 목업 미리보기 · 실제 데이터 변경 없음'),
              ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
  IconData _icon(String kind) => switch (kind) {
    'feed' => Icons.ramen_dining_outlined,
    'walk' => Icons.directions_walk,
    'outfit' => Icons.checkroom_outlined,
    'program' => Icons.schedule,
    'adopt' => Icons.favorite,
    'growth' => Icons.star,
    _ => Icons.check_circle_outline,
  };
}

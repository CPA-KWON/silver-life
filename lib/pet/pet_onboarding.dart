import 'package:flutter/material.dart';

import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_home_pages.dart';
import 'pet_care_pages.dart';

class PetPreviewEntry extends StatelessWidget {
  const PetPreviewEntry({
    super.key,
    required this.pet,
    required this.onTap,
    this.nickname,
  });
  final PetPreviewController pet;
  final VoidCallback onTap;
  final String? nickname;
  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) {
      Widget photo = PetPhoto(pet: pet, height: 120);
      if (!pet.adopted) {
        photo = ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .2126,
            .7152,
            .0722,
            0,
            0,
            .2126,
            .7152,
            .0722,
            0,
            0,
            .2126,
            .7152,
            .0722,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: Opacity(opacity: .55, child: photo),
        );
      }
      final portrait = Container(
        width: 116,
        height: 128,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .8),
          borderRadius: BorderRadius.circular(24),
        ),
        child: photo,
      );
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            pet.adopted ? '나의 반려동물' : 'NEW · 나의 반려동물',
            style: petText(14, color: PetColors.blue),
          ),
          const SizedBox(height: 7),
          if (pet.adopted)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(pet.name!, style: petText(25)),
                PetPill(pet.stageName),
              ],
            )
          else
            Text('함께할 반려동물을\n만나보세요', style: petText(22)),
          const SizedBox(height: 8),
          Text(
            pet.error != null
                ? '서버 연결을 확인해주세요'
                : pet.adopted
                ? '${nickname ?? '회원'}님, 오늘도\n와주셨네요!'
                : '매일 돌보고 활동하면\n함께 자라요',
            style: petText(
              17,
              color: PetColors.secondary,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: pet.busy ? null : onTap,
            style: FilledButton.styleFrom(
              backgroundColor: PetColors.blue,
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: Text(
              pet.adopted ? '${pet.name} 만나러 가기 →' : '반려동물 만나기',
              style: petText(17, color: Colors.white),
            ),
          ),
        ],
      );
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE1F0FC), Color(0xFFF3EFFF)],
          ),
          borderRadius: BorderRadius.circular(30),
        ),
        child: LayoutBuilder(
          builder: (c, b) =>
              b.maxWidth < 300 || MediaQuery.textScalerOf(c).scale(1) > 1.4
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: portrait),
                    const SizedBox(height: 16),
                    content,
                  ],
                )
              : Row(
                  children: [
                    portrait,
                    const SizedBox(width: 18),
                    Expanded(child: content),
                  ],
                ),
        ),
      );
    },
  );
}

class PetAdoptionPage extends StatefulWidget {
  const PetAdoptionPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetAdoptionPage> createState() => _AdoptionState();
}

class _AdoptionState extends State<PetAdoptionPage> {
  final name = TextEditingController(text: '콩이');
  final form = GlobalKey<FormState>();
  bool complete = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> adopt() async {
    if (!form.currentState!.validate()) return;
    try {
      await widget.pet.run('adopt', {'name': name.text});
      if (mounted) setState(() => complete = true);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext c) {
    final pet = widget.pet;
    return PetScreen(
      fullscreen: false,
      colors: const [
        Color(0xFFE1F1FB),
        Color(0xFFF5F0FF),
        PetColors.background,
      ],
      footer: PetPrimary(
        complete ? '콩이 만나러 가기' : '이 이름으로 입양하기',
        onTap: pet.busy
            ? null
            : complete
            ? () => Navigator.pushReplacement(
                c,
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: 'pet'),
                  builder: (_) => PetHomePage(pet: pet),
                ),
              )
            : adopt,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetHeader(
            '반려동물 입양',
            trailing: Text(
              complete ? '2 / 2' : '1 / 2',
              style: petText(17, color: PetColors.muted),
            ),
          ),
          PetPhoto(pet: pet, height: 260, mood: complete ? 'happy' : null),
          const SizedBox(height: 12),
          PetCard(
            padding: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  complete ? '이제 우리 가족이에요' : '새 친구가 왔어요',
                  style: petText(16, color: PetColors.blue),
                ),
                const SizedBox(height: 6),
                Text(
                  complete ? '${pet.name}, 반가워요!' : '이름을 지어 주세요',
                  style: petText(26),
                ),
                const SizedBox(height: 12),
                Text(
                  complete
                      ? '동네에서 활동하고 매일 돌보며 함께 자라요.'
                      : '이름은 나중에 성장 기록에서 바꿀 수 있어요.',
                  style: petText(
                    17,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
                if (!complete) ...[
                  const SizedBox(height: 18),
                  Form(
                    key: form,
                    child: TextFormField(
                      controller: name,
                      maxLength: 6,
                      style: petText(26),
                      decoration: const InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.all(18),
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '이름을 입력해주세요.' : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final n in ['콩이', '보리', '몽실이', '복실이'])
                        ActionChip(
                          label: Text(
                            n,
                            style: petText(16, color: PetColors.blue),
                          ),
                          onPressed: () => setState(() => name.text = n),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '추천 이름을 누르면 바로 입력돼요',
                    style: petText(14, color: PetColors.muted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (pet.isPreview)
            Text(
              '디자인 미리보기 · 실제 포인트와 신청은 변경되지 않아요',
              style: petText(14, color: PetColors.muted),
            ),
        ],
      ),
    );
  }
}

class PetConnectionPage extends StatelessWidget {
  const PetConnectionPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) => PetScreen(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetHeader('반려동물 연결'),
          PetPhoto(pet: pet, height: 250),
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('서버 연결을 준비하고 있어요', style: petText(24)),
                const SizedBox(height: 12),
                Text(
                  '반려동물 상태와 포인트를 안전하게 저장하려면 서버 설정이 필요해요. 기존 출석·포인트는 그대로 보호하고 있어요.',
                  style: petText(
                    18,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                PetPrimary(
                  pet.busy ? '연결 확인 중' : '다시 연결하기',
                  onTap: pet.busy
                      ? null
                      : () async {
                          await pet.load();
                          if (c.mounted && pet.ready) {
                            Navigator.pushReplacement(
                              c,
                              MaterialPageRoute<void>(
                                builder: (_) => pet.adopted
                                    ? PetHomePage(pet: pet)
                                    : PetAdoptionPage(pet: pet),
                              ),
                            );
                          }
                        },
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    final demo = PetPreviewController()..ready = true;
                    Navigator.push(
                      c,
                      MaterialPageRoute<void>(
                        builder: (_) => PetAdoptionPage(pet: demo),
                      ),
                    );
                  },
                  child: const Text('디자인 미리보기 열기'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

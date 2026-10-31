import 'package:flutter/material.dart';

import '../attendance/attendance_controller.dart';
import '../core/release_flags.dart';

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
      final attended =
          AttendanceScope.maybeOf(c)?.status?.attendedToday ?? pet.attended;
      Widget photo = PetPhoto(
        pet: pet,
        height: 140,
        mood: pet.adopted && pet.worn.isEmpty ? 'greeting' : null,
      );
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
        width: 128,
        height: 140,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .75),
          borderRadius: BorderRadius.circular(26),
        ),
        child: Transform.scale(scale: 1.12, child: photo),
      );
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pet.adopted ? '나의 반려동물' : 'NEW · 나의 반려동물',
            style: petText(14, color: PetColors.blue),
          ),
          const SizedBox(height: 3),
          if (pet.adopted)
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(pet.name!, style: petText(26, weight: FontWeight.w800)),
                PetPill(pet.stageName, horizontal: 9, fontSize: 14),
              ],
            )
          else
            Text(
              '함께할 반려동물을\n만나보세요',
              style: petText(21, weight: FontWeight.w800),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              pet.error != null
                  ? '서버 연결을 확인해주세요'
                  : !pet.adopted
                  ? '매일 돌보고 활동하면 함께 자라요'
                  : attended
                  ? '출석, 고마워요! 같이 놀아요'
                  : '오늘도 같이 놀아요!',
              style: petText(
                16,
                color: PetColors.secondary,
                weight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: pet.busy ? null : onTap,
            style: FilledButton.styleFrom(
              backgroundColor: PetColors.blue,
              minimumSize: const Size(0, 50),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: const StadiumBorder(),
            ),
            child: Text(
              pet.adopted ? '${pet.name} 만나러 가기 →' : '반려동물 만나기',
              textAlign: TextAlign.center,
              style: petText(17, color: Colors.white, weight: FontWeight.w800),
            ),
          ),
        ],
      );
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE0F1FB), Color(0xFFEAEEFF)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08086FA9),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: LayoutBuilder(
          builder: (c, b) =>
              b.maxWidth < 310 || MediaQuery.textScalerOf(c).scale(1) > 1.4
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: portrait),
                    const SizedBox(height: 14),
                    content,
                  ],
                )
              : Row(
                  children: [
                    portrait,
                    const SizedBox(width: 14),
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
  final name = TextEditingController();
  final form = GlobalKey<FormState>();
  String? species;
  bool naming = false, complete = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> adopt() async {
    if (!form.currentState!.validate()) return;
    final yes = await petDialog(
      context,
      title: '${name.text.trim()}를 입양할까요?',
      message: '함께 활동하며 자라요. 기존 포인트는 그대로예요.',
      action: '입양하기',
      secondary: '다시 고르기',
    );
    if (!yes || !mounted) return;
    try {
      await widget.pet.run('adopt', {
        'name': name.text.trim(),
        'species': species,
      });
      if (mounted) setState(() => complete = true);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext c) {
    final pet = widget.pet;
    final selected = PetPreviewController()..species = species ?? 'dog';
    return ListenableBuilder(
      listenable: pet,
      builder: (c, _) => PetScreen(
        colors: const [Color(0xFFE8E8FF), PetColors.background],
        footer: PetPrimary(
          complete
              ? '${pet.name} 만나러 가기'
              : naming
              ? '이 이름으로 입양하기'
              : '함께할 친구 선택하기',
          color: PetColors.purple,
          onTap: pet.busy
              ? null
              : complete
              ? () => Navigator.pushReplacement(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => PetHomePage(pet: pet),
                  ),
                )
              : naming
              ? adopt
              : species == null
              ? null
              : () => setState(() {
                  naming = true;
                  name.text = species == 'cat' ? '나비' : '콩이';
                }),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetHeader(
              '반려동물 입양',
              trailing: Text(naming ? '2 / 2' : '1 / 2', style: petText(16)),
            ),
            if (!naming) ...[
              Text('함께할 친구를 골라 주세요', style: petText(26)),
              const SizedBox(height: 8),
              Text(
                '매일 돌보고 동네에서 활동하면 함께 자라요.',
                style: petText(17, color: PetColors.secondary),
              ),
              const SizedBox(height: 20),
              for (final kind in ['dog', 'cat'])
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: InkWell(
                    onTap: () => setState(() => species = kind),
                    borderRadius: BorderRadius.circular(24),
                    child: PetCard(
                      border: Border.all(
                        color: species == kind
                            ? PetColors.purple
                            : Colors.transparent,
                        width: 2,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 105,
                            child: PetPhoto(
                              pet: PetPreviewController()..species = kind,
                              height: 120,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  kind == 'cat' ? '고양이' : '강아지',
                                  style: petText(16, color: PetColors.muted),
                                ),
                                Text(
                                  kind == 'cat' ? '이름을 지어 주세요' : '콩이',
                                  style: petText(24),
                                ),
                                Text(
                                  kind == 'cat'
                                      ? '느긋하고 호기심 많은 새 친구예요.'
                                      : '다정한 강아지와 하루를 함께해요.',
                                  style: petText(
                                    16,
                                    color: PetColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            species == kind
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: species == kind
                                ? PetColors.purple
                                : PetColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Text(
                '한 계정에 한 마리와 함께해요. 선택 후에도 P와 활동 기록은 유지돼요.',
                style: petText(15, color: PetColors.muted),
              ),
            ] else ...[
              PetSpeech(
                complete ? '이제 우리 가족이에요!' : '이름을 지어 주세요!',
                color: PetColors.purple,
              ),
              PetPhoto(
                pet: complete ? pet : selected,
                height: 250,
                mood: complete ? 'happy' : null,
              ),
              PetCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      complete ? '${pet.name}, 반가워요!' : '어떻게 부를까요?',
                      style: petText(26),
                    ),
                    const SizedBox(height: 12),
                    if (!complete)
                      Form(
                        key: form,
                        child: TextFormField(
                          controller: name,
                          maxLength: 6,
                          style: petText(24),
                          decoration: const InputDecoration(
                            hintText: '이름을 지어 주세요',
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return '이름을 입력해주세요.';
                            }
                            if (v.trim().runes.length > 6) {
                              return '6자 이내로 입력해주세요.';
                            }
                            if (!RegExp(r'^[가-힣a-zA-Z0-9 ]+$')
                                .hasMatch(v.trim())) {
                              return '한글·영문·숫자만 사용할 수 있어요.';
                            }
                            return null;
                          },
                        ),
                      ),
                    if (!complete)
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final n
                              in species == 'cat'
                                  ? ['나비', '구름', '모모', '별이']
                                  : ['콩이', '보리', '몽실이', '복실이'])
                            ActionChip(
                              label: Text(n),
                              onPressed: () => setState(() => name.text = n),
                            ),
                        ],
                      ),
                    Text(
                      '이름은 성장 기록에서 바꿀 수 있어요.',
                      style: petText(16, color: PetColors.secondary),
                    ),
                  ],
                ),
              ),
              if (!complete)
                TextButton(
                  onPressed: () => setState(() => naming = false),
                  child: const Text('친구 다시 고르기'),
                ),
            ],
            if (pet.isPreview)
              Text(
                '디자인 미리보기 · 실제 포인트는 변경되지 않아요',
                style: petText(14, color: PetColors.muted),
              ),
          ],
        ),
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
                Text(
                  isReleaseBuild ? '반려동물을 불러오지 못했어요' : '서버 연결을 준비하고 있어요',
                  style: petText(24),
                ),
                const SizedBox(height: 12),
                Text(
                  isReleaseBuild ? '인터넷 연결을 확인한 뒤 다시 시도해 주세요.' : '반려동물 상태와 포인트를 안전하게 저장하려면 서버 설정이 필요해요. 기존 출석·포인트는 그대로 보호하고 있어요.',
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
                if (!isReleaseBuild) ...[
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
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/release_flags.dart';
import 'pet_design.dart';
import 'pet_preview_controller.dart';

class PetGrowthPage extends StatefulWidget {
  const PetGrowthPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetGrowthPage> createState() => _GrowthState();
}

class _GrowthState extends State<PetGrowthPage> {
  Timer? timer;
  bool celebrating = false;
  late final previous = (widget.pet.stage - 1).clamp(0, 1);
  @override
  void initState() {
    super.initState();
    timer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => celebrating = true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final pet = widget.pet;
    return AnnotatedRegion(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F0FF),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF4F0FF), Color(0xFFE4EFF9)],
            ),
          ),
          child: CustomPaint(
            painter: PetRays(),
            child: SafeArea(
              child: celebrating
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 32),
                          PetSpeech(
                            pet.stage == 1
                                ? '함께해 준 덕분에 쑥 컸어요!'
                                : '이제 든든한 ${pet.name}예요!',
                            color: PetColors.purple,
                          ),
                          PetPhoto(pet: pet, height: 330, mood: 'happy'),
                          const SizedBox(height: 14),
                          PetCard(
                            padding: 20,
                            child: Column(
                              children: [
                                PetPill(
                                  '${['아기', '성장기'][previous]} → ${pet.stageName}',
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '${pet.name}가 ${pet.stage == 1 ? '성장기가' : '어른이'} 되었어요!',
                                  textAlign: TextAlign.center,
                                  style: petText(25),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: PetCard(
                                        color: const Color(0xFFF5F8FB),
                                        padding: 4,
                                        child: PetPhoto(
                                          pet: pet,
                                          height: 90,
                                          stage: previous,
                                          outfit: const {},
                                        ),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      child: Icon(
                                        Icons.arrow_forward_rounded,
                                        color: PetColors.purple,
                                        size: 32,
                                      ),
                                    ),
                                    Expanded(
                                      child: PetCard(
                                        color: PetColors.lavender,
                                        padding: 4,
                                        child: PetPhoto(pet: pet, height: 90),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _change(
                                  1,
                                  pet.stage == 1
                                      ? (pet.isCat
                                            ? '꼬리가 길어지고 다리가 쑥 자랐어요'
                                            : '귀가 길어지고 다리가 쑥 자랐어요')
                                      : (pet.isCat
                                            ? '또렷한 줄무늬와 긴 꼬리, 듬직한 몸'
                                            : '차분한 눈썹과 긴 귀, 듬직한 몸'),
                                ),
                                if (pet.stage == 1 || !isReleaseBuild) ...[
                                  const SizedBox(height: 8),
                                  _change(
                                    2,
                                    pet.stage == 1
                                        ? (pet.isCat
                                              ? '베레모와 연두 우비를 입혀볼 수 있어요'
                                              : '산책 챙모자와 노란 우비가 열렸어요')
                                        : '성체 전용 산책 코스는 준비 중이에요',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          PetPrimary(
                            '새 모습 보러 가기',
                            color: PetColors.purple,
                            onTap: () => Navigator.pop(c),
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    )
                  : InkWell(
                      onTap: () => setState(() => celebrating = true),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Spacer(),
                          PetPhoto(pet: pet, height: 300, silhouette: true),
                          const SizedBox(height: 50),
                          Text(
                            '${pet.name}가 자라고 있어요...',
                            textAlign: TextAlign.center,
                            style: petText(28),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '빛이 사라지면 새로운 모습이 나타나요',
                            textAlign: TextAlign.center,
                            style: petText(18, color: PetColors.secondary),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              '화면을 누르면 건너뛸 수 있어요',
                              textAlign: TextAlign.center,
                              style: petText(16, color: PetColors.muted),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _change(int n, String text) => PetCard(
    color: const Color(0xFFF6F8FB),
    padding: 14,
    child: Row(
      children: [
        PetPill('$n'),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: petText(17))),
      ],
    ),
  );
}

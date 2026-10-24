import 'dart:async';

import 'package:flutter/material.dart';

import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_character.dart';
import 'pet_care_pages.dart';
import 'pet_growth_pages.dart';
import 'pet_walk_page.dart';
import 'pet_today_page.dart';
import 'pet_record_pages.dart';

Future<T?> petOpen<T>(BuildContext c, Widget page, {bool fullscreen = false}) =>
    (fullscreen
            ? PetNavigationScope.maybeOf(c) ?? Navigator.of(c)
            : Navigator.of(c))
        .push<T>(MaterialPageRoute(builder: (_) => page));

class PetHomePage extends StatefulWidget {
  const PetHomePage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetHomePage> createState() => _PetHomeState();
}

class _PetHomeState extends State<PetHomePage> {
  String? phase;
  PetFood? lastFood;
  bool feeding = false;
  bool greeting = true;
  Timer? greetingTimer;
  @override
  void initState() {
    super.initState();
    greetingTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => greeting = false);
    });
  }

  @override
  void dispose() {
    greetingTimer?.cancel();
    super.dispose();
  }

  Future<void> feed() async {
    if (feeding) return;
    final pet = widget.pet;
    final food = await showPetFoodPicker(context, pet);
    if (food == null || !mounted) return;
    if (food.price > 0 &&
        !await petDialog(
          context,
          title: '${food.name}을 살까요?',
          message: '사고 나면 바로 먹여줄 수 있어요.',
          emblem: FoodDrawing(food.id),
          rows: [
            ('가격', '${food.price}P'),
            ('지금 포인트', '${petNumber(pet.points)}P'),
            ('구매 후 남는 포인트', '${petNumber(pet.points - food.price)}P'),
          ],
          action: '구매하기',
          secondary: '취소',
        )) {
      return;
    }
    if (!mounted) return;
    try {
      setState(() => feeding = true);
      final result = await pet.run('feed', {'item': food.id});
      if (!mounted) return;
      setState(() {
        phase = 'eating';
        lastFood = food;
      });
      await Future<void>.delayed(
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1500),
      );
      if (!mounted) return;
      setState(() => phase = 'happy');
      await Future<void>.delayed(
        MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 1000),
      );
      if (!mounted) return;
      await petDialog(
        context,
        title: '${food.name}${food.id == 'food' ? '를' : '을'} 줬어요',
        message: '${pet.name}가 맛있게 먹었어요.',
        emblem: FoodDrawing(food.id),
        rows: [
          ('배부름', '+${food.fullness}칸'),
          ('성장 경험치', '+${result.experience} EXP'),
          if (food.id == 'sweet') ('남은 고구마 간식', '${pet.snacks['sweet'] ?? 0}개'),
        ],
      );
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    } finally {
      if (mounted) {
        setState(() {
          phase = null;
          feeding = false;
        });
      }
    }
  }

  Future<void> grow() async {
    try {
      await widget.pet.run('grow');
      if (mounted) {
        await petOpen(
          context,
          PetGrowthPage(pet: widget.pet),
          fullscreen: true,
        );
      }
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  Future<void> rotate() => showModalBottomSheet<void>(
    context: petModalContext(context),
    useRootNavigator: false,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
    ),
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('좌우로 돌려보세요', style: petText(24)),
          const SizedBox(height: 8),
          Text(
            '실제 입체 보기예요. 원본 이미지와 외형 차이가 있어요.',
            style: petText(
              16,
              color: PetColors.secondary,
              weight: FontWeight.w500,
            ),
          ),
          PetCharacter(pet: widget.pet, height: 300),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('닫기'),
          ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: widget.pet,
    builder: (c, _) {
      final pet = widget.pet;
      final bubble = phase == 'eating'
          ? '냠냠, 맛있어요!'
          : phase == 'happy'
          ? '고마워요!'
          : pet.canGrow
          ? '몸이 근질근질해요!'
          : pet.fullness < 2
          ? '배고파요...'
          : pet.stage == 1
          ? '오늘도 같이 놀아요!'
          : '오늘도 만나서 반가워요!';
      return PetScreen(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetHeader(pet.name ?? '콩이', pet: pet, stage: pet.stageName),
            const SizedBox(height: 12),
            PetSpeech(bubble),
            LayoutBuilder(
              builder: (c, b) {
                final large = MediaQuery.textScalerOf(c).scale(1) > 1.5;
                final actions =
                    <
                      ({
                        IconData icon,
                        String label,
                        Color color,
                        Color tint,
                        VoidCallback tap,
                      })
                    >[
                      (
                        icon: Icons.ramen_dining_outlined,
                        label: '먹이 주기',
                        color: PetColors.orange,
                        tint: const Color(0xFFFFF7E9),
                        tap: feed,
                      ),
                      (
                        icon: Icons.directions_walk,
                        label: '산책하기',
                        color: PetColors.green,
                        tint: const Color(0xFFEFFAF3),
                        tap: () =>
                            petOpen(c, PetWalkPage(pet: pet), fullscreen: true),
                      ),
                      (
                        icon: Icons.checkroom_outlined,
                        label: '옷 입히기',
                        color: PetColors.pink,
                        tint: PetColors.pinkTint,
                        tap: () => petOpen(
                          c,
                          PetWardrobePage(pet: pet),
                          fullscreen: true,
                        ),
                      ),
                      (
                        icon: Icons.bar_chart,
                        label: '성장 기록',
                        color: PetColors.blue,
                        tint: const Color(0xFFEAF4FC),
                        tap: () => petOpen(c, PetRecordsPage(pet: pet)),
                      ),
                    ];
                Widget button(int i) => Semantics(
                  button: true,
                  child: InkWell(
                    onTap: feeding ? null : actions[i].tap,
                    borderRadius: BorderRadius.circular(22),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: actions[i].tint,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i == 0 && phase != null
                                  ? PetColors.blue
                                  : Colors.white,
                              width: 3,
                            ),
                            boxShadow: PetColors.softShadow,
                          ),
                          child: PetLineIcon(
                            actions[i].icon,
                            color: actions[i].color,
                            size: 31,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          actions[i].label,
                          textAlign: TextAlign.center,
                          style: petText(17),
                        ),
                      ],
                    ),
                  ),
                );
                if (large) {
                  return Column(
                    children: [
                      PetPhoto(
                        pet: pet,
                        mood:
                            phase ??
                            (greeting &&
                                    !MediaQuery.disableAnimationsOf(c) &&
                                    pet.stage == 0 &&
                                    pet.worn.isEmpty
                                ? 'hello'
                                : null),
                        height: 260,
                      ),
                      Wrap(
                        spacing: 18,
                        runSpacing: 12,
                        children: [for (var i = 0; i < 4; i++) button(i)],
                      ),
                    ],
                  );
                }
                return SizedBox(
                  height: b.maxWidth * .74,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        left: 36,
                        right: 36,
                        child: PetPhoto(
                          pet: pet,
                          mood:
                              phase ??
                              (greeting &&
                                      !MediaQuery.disableAnimationsOf(c) &&
                                      pet.stage == 0 &&
                                      pet.worn.isEmpty
                                  ? 'hello'
                                  : null),
                          height: b.maxWidth * .74,
                        ),
                      ),
                      Positioned(left: 0, top: 14, child: button(0)),
                      Positioned(right: 0, top: 14, child: button(1)),
                      Positioned(
                        left: 0,
                        top: b.maxWidth * .40,
                        child: button(2),
                      ),
                      Positioned(
                        right: 0,
                        top: b.maxWidth * .40,
                        child: button(3),
                      ),
                      if (phase == 'happy')
                        const Positioned(
                          top: 45,
                          left: 100,
                          child: Icon(
                            Icons.favorite,
                            color: PetColors.pink,
                            size: 26,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (phase == null)
              Center(
                child: TextButton.icon(
                  onPressed: rotate,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.rotate_right, size: 22),
                  label: Text(
                    '좌우로 돌리기',
                    style: petText(16, color: PetColors.secondary),
                  ),
                ),
              )
            else
              Center(
                child: PetPill(
                  phase == 'eating'
                      ? '${lastFood?.name}을 먹고 있어요'
                      : '✓ 배부름 +${lastFood?.fullness} · 성장 경험치 +${lastFood?.xp}',
                  color: phase == 'eating' ? PetColors.ink : PetColors.green,
                  ink: Colors.white,
                ),
              ),
            const SizedBox(height: 12),
            PetStats(pet),
            const SizedBox(height: 24),
            _HomeCallout(
              pet: pet,
              grow: grow,
              onToday: () => petOpen(c, PetTodayPage(pet: pet)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      );
    },
  );
}

class _HomeCallout extends StatelessWidget {
  const _HomeCallout({
    required this.pet,
    required this.grow,
    required this.onToday,
  });
  final PetPreviewController pet;
  final VoidCallback grow, onToday;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: pet.canGrow
            ? const [Color(0xFF6A57FF), Color(0xFF9A88FF)]
            : const [Color(0xFF0879B6), Color(0xFF2995CD)],
      ),
      borderRadius: BorderRadius.circular(24),
      boxShadow: [
        BoxShadow(
          color: (pet.canGrow ? PetColors.purple : PetColors.blue).withValues(
            alpha: .22,
          ),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            Text(
              pet.canGrow ? '성장할 준비가 됐어요!' : '오늘의 활동',
              style: petText(23, color: Colors.white),
            ),
            FilledButton(
              onPressed: pet.busy
                  ? null
                  : pet.canGrow
                  ? grow
                  : onToday,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: pet.canGrow
                    ? PetColors.purple
                    : PetColors.blue,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 10,
                ),
                shape: const StadiumBorder(),
              ),
              child: Text(
                pet.canGrow ? '성장시키기 →' : '하러 가기 →',
                style: petText(
                  17,
                  color: pet.canGrow ? PetColors.purple : PetColors.blue,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          pet.canGrow
              ? '성장 경험치를 모두 모았어요 · ${pet.stageName} → ${pet.stage == 0 ? '성장기' : '성체'}'
              : '${pet.attended ? '출석 완료' : '출석 전'} · 미션 ${pet.missions.where((m) => m['completed'] == true).length}/3 · 참여 확인 대기 ${pet.programs.where((p) => p['status'] == 'approved' || p['status'] == 'applied').length}건',
          style: petText(15, color: Colors.white, weight: FontWeight.w500),
        ),
      ],
    ),
  );
}

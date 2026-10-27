import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pet/pet_design.dart';

const activityQuickCategories = <String, String>{
  '운동': '건강·운동',
  '취미': '문화·취미',
  '교육': '배움·디지털',
  '건강': '건강·운동',
};

/// Presentation only: the shell's wallet and pet repository provide the data.
class ActivityWalletPill extends StatelessWidget {
  const ActivityWalletPill({super.key, this.balance, required this.onTap});
  final int? balance;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    excludeSemantics: true,
    onTap: onTap,
    label: balance == null ? '포인트와 출석체크 열기' : '보유 포인트 $balance포인트, 출석체크 열기',
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
      child: InkWell(
        borderRadius: BorderRadius.circular(32),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.5,
                    colors: [
                      Color(0xFFFFEEA0),
                      Color(0xFFFFCD36),
                      Color(0xFFF0AA0E),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  balance == null ? '포인트' : '${petNumber(balance!)} P',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: petText(18),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 19,
                color: Color(0xFF99A9B8),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ActivityDiscoveryCard extends StatelessWidget {
  const ActivityDiscoveryCard({
    super.key,
    required this.controller,
    required this.onFind,
    required this.onSearch,
    required this.onCategory,
  });
  final TextEditingController controller;
  final VoidCallback onFind;
  final ValueChanged<String> onSearch, onCategory;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(
        colors: [Color(0xFF0874AA), Color(0xFF3D98D0)],
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18086B9A),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Stack(
      children: [
        Positioned(
          right: -37,
          top: -52,
          child: Container(
            width: 165,
            height: 165,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .08),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onFind,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '맞춤 활동 찾기',
                        style: petText(
                          25,
                          color: Colors.white,
                          weight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '조건에 맞는 활동과 전체 프로그램을 찾아요',
                        style: petText(
                          16,
                          color: const Color(0xFFE6F4FF),
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextField(
                key: const ValueKey('activity-hub-search'),
                controller: controller,
                textInputAction: TextInputAction.search,
                onSubmitted: onSearch,
                style: petText(18),
                decoration: InputDecoration(
                  hintText: '어떤 활동을 찾으세요?',
                  hintStyle: petText(17, color: const Color(0xFF8293A2)),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 26,
                    color: Color(0xFF8798A6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 19,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(
                      color: Color(0xFFBDE7FA),
                      width: 2,
                    ),
                  ),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(8),
                    child: IconButton.filled(
                      tooltip: '활동 검색',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF0878B4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () => onSearch(controller.text),
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in activityQuickCategories.keys)
                    OutlinedButton(
                      onPressed: () => onCategory(label),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: .16),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: .35),
                        ),
                        shape: const StadiumBorder(),
                        minimumSize: const Size(50, 42),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        label,
                        style: petText(18, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ActivityWeeklyCard extends StatelessWidget {
  const ActivityWeeklyCard({
    super.key,
    required this.missions,
    required this.loaded,
    required this.adopted,
    required this.hasError,
    required this.onTap,
  });
  final List<Map<String, dynamic>> missions;
  final bool loaded, adopted, hasError;
  final VoidCallback onTap;
  static const labels = ['출석 3일', '함께 활동 1회', '프로그램 1회'];
  @override
  Widget build(BuildContext context) {
    final ordered = List<Map<String, dynamic>>.generate(
      3,
      (i) => missions.firstWhere((m) => m['stage'] == i + 1, orElse: () => {}),
    );
    final completed = ordered.where((m) => m['claimed'] == true).length;
    final next = ordered.indexWhere((m) => m['claimed'] != true);
    final current = next < 0 ? 2 : next;
    final message = !loaded
        ? hasError
              ? '미션 정보를 다시 확인해주세요'
              : '미션 진행 상황을 확인하고 있어요'
        : !adopted
        ? '콩이를 입양하고 미션 보상을 받아보세요'
        : next < 0
        ? '이번 주 미션을 모두 마쳤어요'
        : ordered[current]['completed'] == true
        ? '${labels[current]} 보상 받기'
        : labels[current];
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF5D9), Color(0xFFFDECF5)],
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06A47D4A),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(30),
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.outlined_flag_rounded,
                            color: Color(0xFFEF8F0B),
                            size: 27,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            '주간 미션',
                            style: petText(23, weight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        loaded
                            ? '$completed / 3단계'
                            : hasError
                            ? '다시 확인'
                            : '확인 중',
                        style: petText(17, color: const Color(0xFFD96A0C)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 21),
                LayoutBuilder(
                  builder: (c, b) {
                    Widget step(int i, {bool vertical = false}) => _MissionStep(
                      index: i,
                      label: labels[i],
                      done: loaded && ordered[i]['claimed'] == true,
                      current: loaded && adopted && next == i,
                      vertical: vertical,
                    );
                    if (MediaQuery.textScalerOf(c).scale(1) > 1.45 ||
                        b.maxWidth < 255) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: step(i, vertical: true),
                            ),
                        ],
                      );
                    }
                    return Stack(
                      children: [
                        Positioned(
                          top: 22,
                          left: b.maxWidth / 6,
                          right: b.maxWidth / 6,
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        if (completed > 0)
                          Positioned(
                            top: 22,
                            left: b.maxWidth / 6,
                            child: Container(
                              width: (b.maxWidth * 2 / 3) * (completed / 3),
                              height: 5,
                              color: const Color(0xFFFF9E25),
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Expanded(child: step(i)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: loaded && adopted && next >= 0
                                    ? '다음 미션  '
                                    : '',
                                style: petText(16, color: PetColors.secondary),
                              ),
                              TextSpan(text: message, style: petText(17)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '보기 ›',
                        style: petText(17, color: const Color(0xFFD96A0C)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionStep extends StatelessWidget {
  const _MissionStep({
    required this.index,
    required this.label,
    required this.done,
    required this.current,
    this.vertical = false,
  });
  final int index;
  final String label;
  final bool done, current, vertical;
  @override
  Widget build(BuildContext context) {
    final circle = SizedBox(
      width: 46,
      height: 46,
      child: CustomPaint(
        painter: _StepRing(current: current, done: done),
        child: Center(
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 26)
              : Text(
                  '${index + 1}',
                  style: petText(
                    20,
                    color: current
                        ? const Color(0xFFE37A0F)
                        : const Color(0xFFA99D8B),
                  ),
                ),
        ),
      ),
    );
    final caption = Text(
      label,
      textAlign: TextAlign.center,
      style: petText(15, color: const Color(0xFF967A59)),
    );
    return Semantics(
      label:
          '$label, ${done
              ? '보상 수령 완료'
              : current
              ? '다음 미션'
              : '진행 전'}',
      excludeSemantics: true,
      child: vertical
          ? Row(
              children: [
                circle,
                const SizedBox(width: 12),
                Expanded(child: caption),
              ],
            )
          : Column(children: [circle, const SizedBox(height: 8), caption]),
    );
  }
}

class _StepRing extends CustomPainter {
  const _StepRing({required this.current, required this.done});
  final bool current, done;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawOval(
      rect,
      Paint()
        ..color = done
            ? const Color(0xFFFFA129)
            : Colors.white.withValues(alpha: .95),
    );
    if (current) {
      final paint = Paint()
        ..color = const Color(0xFFF4961D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      for (var i = 0; i < 15; i++) {
        canvas.drawArc(
          rect.deflate(1.5),
          i * math.pi * 2 / 15,
          math.pi * 2 / 15 * .65,
          false,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StepRing old) =>
      old.current != current || old.done != done;
}

class ActivityPurposeTile extends StatelessWidget {
  const ActivityPurposeTile({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.tint,
    required this.onTap,
  });
  final String title, description;
  final IconData icon;
  final Color color, tint;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: tint,
    borderRadius: BorderRadius.circular(30),
    child: InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .92),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: color, size: 31),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right_rounded, color: color),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(title, style: petText(23, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              description,
              style: petText(
                16,
                color: PetColors.secondary,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

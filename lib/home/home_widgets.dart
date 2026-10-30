import '../core/points.dart';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/attendance_repository.dart';
import '../pet/pet_design.dart';

/// Home-only presentation. Existing destinations, wallet and reward rules are
/// shared with the rest of the application.
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.child,
    this.padding = 18,
    this.colors,
    this.onTap,
  });
  final Widget child;
  final double padding;
  final List<Color>? colors;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: colors == null ? Colors.white : null,
      gradient: colors == null
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors!,
            ),
      borderRadius: BorderRadius.circular(28),
      boxShadow: const [
        BoxShadow(
          color: Color(0x07182D40),
          blurRadius: 20,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      ),
    ),
  );
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.nickname,
    required this.onProfile,
    required this.onCalendar,
  });
  final String nickname;
  final VoidCallback onProfile, onCalendar;
  @override
  Widget build(BuildContext context) {
    final status = AttendanceScope.maybeOf(context)?.status;
    final now = DateTime.now().toUtc().add(const Duration(hours: 9));
    final today = status?.today ?? now;
    final date =
        '${today.month}월 ${today.day}일 ${['월', '화', '수', '목', '금', '토', '일'][today.weekday - 1]}요일';
    final profile = InkWell(
      onTap: onProfile,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Center(
                child: Container(
                  key: const ValueKey('home-profile-icon'),
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x080F2B43), blurRadius: 12),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text('내 정보', style: petText(12)),
          ],
        ),
      ),
    );
    final points = Semantics(
      container: true,
      button: true,
      onTap: onCalendar,
      label: status == null
          ? '포인트와 출석체크 열기'
          : '보유 포인트 ${pointAmount(status.balance)}포인트, 출석체크 열기',
      excludeSemantics: true,
      child: TextButton(
        key: const ValueKey('home-points'),
        onPressed: onCalendar,
        style: TextButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: PetColors.ink,
          minimumSize: const Size(0, 56),
          padding: EdgeInsets.zero,
          shape: const StadiumBorder(),
          elevation: 0,
          shadowColor: const Color(0x160F2B43),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C152B3E),
                blurRadius: 12,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 29,
                height: 29,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.4,
                    colors: [
                      Color(0xFFFFEF9D),
                      Color(0xFFFFCC32),
                      Color(0xFFEFAA0D),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  status == null ? '포인트' : '${pointAmount(status.balance)} P',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: petText(17),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFF98AABA),
              ),
            ],
          ),
        ),
      ),
    );
    final dateLabel = Row(
      key: const ValueKey('home-date'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF32C39A),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(date, style: petText(14, color: PetColors.secondary)),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, b) {
              final large =
                  MediaQuery.textScalerOf(context).scale(1) > 1.4 ||
                  b.maxWidth < 310;
              return large
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        dateLabel,
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.start,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: b.maxWidth),
                              child: points,
                            ),
                            profile,
                          ],
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 56,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: dateLabel,
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: b.maxWidth * .45,
                          ),
                          child: points,
                        ),
                        const SizedBox(width: 2),
                        profile,
                      ],
                    );
            },
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: '안녕하세요, '),
                TextSpan(
                  text: nickname,
                  style: const TextStyle(color: AppColors.primary),
                ),
                const TextSpan(text: '님'),
              ],
            ),
            style: petText(27, weight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '오늘도 동네에서 즐거운 하루 보내세요',
            style: petText(
              17,
              color: PetColors.secondary,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeAttendanceCard extends StatefulWidget {
  const HomeAttendanceCard({
    super.key,
    required this.onCalendar,
    this.onStamped,
  });
  final VoidCallback onCalendar;
  final Future<void> Function()? onStamped;
  @override
  State<HomeAttendanceCard> createState() => _HomeAttendanceCardState();
}

class _HomeAttendanceCardState extends State<HomeAttendanceCard> {
  AttendanceController? controller;
  Future<List<AttendanceDay>>? week;
  String? weekKey;
  bool busy = false;
  String? error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = AttendanceScope.maybeOf(context);
    if (!identical(c, controller)) {
      controller = c;
      weekKey = null;
    }
    final s = c?.status;
    if (s != null) {
      final key = '${s.today}/${s.attendedToday}/${s.streak}';
      if (key != weekKey) {
        weekKey = key;
        week = c!.repository.week(s.today);
      }
    }
  }

  Future<void> stamp() async {
    if (busy || controller == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    var confirmed = false;
    try {
      await controller!.checkIn();
      confirmed = true;
    } catch (_) {
      final s = await controller!.refresh();
      confirmed = s?.attendedToday == true;
      if (!confirmed) error = '출석을 처리하지 못했어요. 다시 시도해주세요.';
    }
    if (confirmed && mounted) {
      try {
        await widget.onStamped?.call();
      } catch (_) {
        error = '출석은 완료됐어요. 콩이의 성장 기록은 다시 확인해주세요.';
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = controller?.status;
    if (controller == null) return const SizedBox.shrink();
    return HomeCard(
      onTap: busy ? null : widget.onCalendar,
      padding: 18,
      colors: const [Color(0xFFFFF5DA), Color(0xFFFFEDF2)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Color(0x0CDA9418), blurRadius: 10),
                      ],
                    ),
                    child: const Icon(
                      Icons.event_available_outlined,
                      color: Color(0xFFF18700),
                      size: 25,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('출석체크', style: petText(22, weight: FontWeight.w800)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department_rounded,
                      color: Color(0xFFE96716),
                      size: 19,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s == null
                          ? '기록 확인'
                          : s.streak == 0
                          ? '오늘부터 시작'
                          : '${s.streak}일 연속',
                      style: petText(14, color: const Color(0xFFCE5A0A)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (s == null) ...[
            Text(
              '출석 정보를 불러오지 못했어요.',
              style: petText(17, color: PetColors.secondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onCalendar,
              child: const Text('출석 정보 다시 확인'),
            ),
          ] else
            FutureBuilder<List<AttendanceDay>>(
              future: week,
              builder: (context, snapshot) {
                final monday = DateTime(
                  s.today.year,
                  s.today.month,
                  s.today.day - s.today.weekday + 1,
                );
                final dates = (snapshot.data ?? []).map((d) => d.date).toSet();
                if (s.attendedToday) dates.add(s.today);
                final loaded =
                    snapshot.connectionState == ConnectionState.done &&
                    !snapshot.hasError;
                final nextBonus = upcomingMilestones(s).firstOrNull;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      button: true,
                      label: '이번 주 출석 기록, 출석 달력 열기',
                      child: InkWell(
                        onTap: widget.onCalendar,
                        borderRadius: BorderRadius.circular(18),
                        child: LayoutBuilder(
                          builder: (context, b) {
                            final large =
                                MediaQuery.textScalerOf(context).scale(1) > 1.4;
                            final count = large
                                ? (b.maxWidth / 76).floor().clamp(1, 7)
                                : 7;
                            return Wrap(
                              runSpacing: 12,
                              children: [
                                for (var i = 0; i < 7; i++)
                                  SizedBox(
                                    width: b.maxWidth / count,
                                    child: _HomeAttendanceDay(
                                      date: DateTime(
                                        monday.year,
                                        monday.month,
                                        monday.day + i,
                                      ),
                                      today: s.today,
                                      attended: dates.contains(
                                        DateTime(
                                          monday.year,
                                          monday.month,
                                          monday.day + i,
                                        ),
                                      ),
                                      known: loaded || i + 1 == s.today.weekday,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const ValueKey('home-attendance-action'),
                      onPressed: busy
                          ? null
                          : s.attendedToday
                          ? widget.onCalendar
                          : stamp,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF237F50),
                        disabledBackgroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: busy
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (s.attendedToday) ...[
                                  const Icon(Icons.check_rounded, size: 25),
                                  const SizedBox(width: 7),
                                ],
                                Flexible(
                                  child: Text(
                                    s.attendedToday
                                        ? '오늘 출석 완료!${s.todayPoints == null ? '' : '  +${pointAmount(s.todayPoints)}P 받았어요'}'
                                        : '출석체크하고 ${pointAmount(attendanceMilestonePoints[s.streak + 1] ?? attendanceBasePoints)}P 받기',
                                    textAlign: TextAlign.center,
                                    style: petText(
                                      18,
                                      color: const Color(0xFF237F50),
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          error!,
                          style: petText(16, color: AppColors.danger),
                        ),
                      ),
                    if (snapshot.hasError)
                      TextButton(
                        onPressed: () => setState(() {
                          week = controller!.repository.week(s.today);
                        }),
                        child: const Text('주간 기록 다시 불러오기'),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            !loaded
                                ? snapshot.hasError
                                      ? '주간 기록을 확인해주세요'
                                      : '출석 기록 확인 중'
                                : '이번 주 ${dates.length}일 출석 · ${nextBonus == null ? '꾸준히 함께해요' : '${nextBonus.streak}일 연속 보너스'}',
                            style: petText(
                              13,
                              color: const Color(0xFF8E6A4D),
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            '출석 달력 ›',
                            style: petText(14, color: const Color(0xFF8E6A4D)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _HomeAttendanceDay extends StatelessWidget {
  const _HomeAttendanceDay({
    required this.date,
    required this.today,
    required this.attended,
    required this.known,
  });
  final DateTime date, today;
  final bool attended, known;
  @override
  Widget build(BuildContext context) {
    final current = date == today;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '${current ? '오늘, ' : ''}${date.month}월 ${date.day}일, ${attended
              ? '출석 완료'
              : !known
              ? '기록 확인 중'
              : date.isAfter(today)
              ? '예정'
              : '출석 전'}',
      child: Column(
        children: [
          Text(
            ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1],
            style: petText(
              14,
              color: current
                  ? const Color(0xFFF07800)
                  : const Color(0xFF92724E),
            ),
          ),
          const SizedBox(height: 7),
          Container(
            width: 46,
            height: 46,
            padding: current ? const EdgeInsets.all(3) : EdgeInsets.zero,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: current
                  ? Border.all(color: const Color(0xFFFF9B23), width: 2.5)
                  : null,
              color: current ? Colors.white : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: attended ? null : Colors.white.withValues(alpha: .85),
                gradient: attended
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFBA4D), Color(0xFFFF961C)],
                      )
                    : null,
                boxShadow: attended
                    ? const [
                        BoxShadow(
                          color: Color(0x32FBB23C),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: attended
                    ? const Icon(
                        Icons.pets_rounded,
                        size: 23,
                        color: Colors.white,
                      )
                    : Text(
                        '${date.day}',
                        style: petText(15, color: const Color(0xFFAB9783)),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomeExploreTile extends StatelessWidget {
  const HomeExploreTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.ink,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final List<Color> colors;
  final Color ink;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HomeCard(
    padding: 0,
    colors: colors,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: icon == Icons.star_outline_rounded
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              color: Color(0xFFFFCE5B),
                              size: 30,
                            ),
                            Icon(
                              Icons.star_outline_rounded,
                              color: ink,
                              size: 30,
                            ),
                          ],
                        )
                      : Icon(icon, color: ink, size: 30),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: ink,
                    size: 23,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(title, style: petText(20, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              subtitle,
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

class HomeMeetupIcon extends StatelessWidget {
  const HomeMeetupIcon({super.key});
  @override
  Widget build(BuildContext context) =>
      const CustomPaint(size: Size(36, 36), painter: _HomeMeetupIconPainter());
}

class _HomeMeetupIconPainter extends CustomPainter {
  const _HomeMeetupIconPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 36, size.height / 36);
    final stroke = Paint()
      ..color = PetColors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 8, 26, 25),
        const Radius.circular(5),
      ),
      stroke,
    );
    canvas.drawLine(const Offset(5, 16), const Offset(31, 16), stroke);
    canvas.drawLine(const Offset(12, 4), const Offset(12, 11), stroke);
    canvas.drawLine(const Offset(24, 4), const Offset(24, 11), stroke);
    final fill = Paint()..color = PetColors.blue;
    canvas.drawCircle(const Offset(13, 24), 3.1, fill);
    canvas.drawCircle(const Offset(23, 24), 3.1, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

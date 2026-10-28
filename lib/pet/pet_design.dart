import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pet_preview_controller.dart';

/// Fullscreen pet routes belong to the signed-in Navigator, so sign-out removes them.
class PetNavigationScope extends InheritedWidget {
  const PetNavigationScope({
    super.key,
    required this.navigator,
    required super.child,
  });
  final NavigatorState navigator;
  static NavigatorState? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<PetNavigationScope>()?.navigator;
  @override
  bool updateShouldNotify(PetNavigationScope old) => navigator != old.navigator;
}

BuildContext petModalContext(BuildContext c) =>
    PetNavigationScope.maybeOf(c)?.overlay?.context ?? c;

abstract final class PetColors {
  static const ink = Color(0xFF142230),
      secondary = Color(0xFF53677A),
      blue = Color(0xFF0878B4),
      sky = Color(0xFFD8EDF9),
      background = Color(0xFFF0F5F9),
      purple = Color(0xFF6250E6),
      lavender = Color(0xFFEFEBFF),
      mint = Color(0xFFE4F5EB),
      green = Color(0xFF278953),
      yellow = Color(0xFFFFF3D3),
      orange = Color(0xFFDA870B),
      pink = Color(0xFFE44983),
      pinkTint = Color(0xFFFFEFF5),
      line = Color(0xFFE6EDF2),
      muted = Color(0xFF6D8193);
  static const skyGradient = [sky, background];
  static const softShadow = [
    BoxShadow(color: Color(0x0C233E54), blurRadius: 20, offset: Offset(0, 6)),
  ];
}

String petNumber(int n) =>
    n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
TextStyle petText(
  double size, {
  Color color = PetColors.ink,
  FontWeight weight = FontWeight.w700,
}) => TextStyle(fontSize: size, color: color, fontWeight: weight, height: 1.32);

class PetCard extends StatelessWidget {
  const PetCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 20,
    this.margin = 0,
    this.border,
  });
  final Widget child;
  final Color color;
  final double padding, margin;
  final Border? border;
  @override
  Widget build(BuildContext c) => Padding(
    padding: EdgeInsets.only(bottom: margin),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: border?.top ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class PetPill extends StatelessWidget {
  const PetPill(
    this.text, {
    super.key,
    this.color = PetColors.lavender,
    this.ink = PetColors.purple,
    this.icon,
    this.fontSize = 15,
    this.horizontal = 12,
  });
  final double fontSize, horizontal;
  final String text;
  final Color color, ink;
  final IconData? icon;
  @override
  Widget build(BuildContext c) => Container(
    padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(30),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: ink),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: petText(fontSize, color: ink),
          ),
        ],
      ),
    ),
  );
}

class PetPoints extends StatelessWidget {
  const PetPoints(this.pet, {super.key});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext c) => Semantics(
    button: true,
    label: pet.isPreview
        ? '디자인 미리보기 포인트 ${pet.points}'
        : '보유 포인트 ${pet.points}',
    child: InkWell(
      borderRadius: BorderRadius.circular(40),
      onTap: () => showDialog<void>(
        context: petModalContext(c),
        useRootNavigator: false,
        builder: (d) => AlertDialog(
          title: Text(pet.isPreview ? '디자인 미리보기' : '내 포인트'),
          content: Text(
            pet.isPreview
                ? '목업을 확인하는 임시 데이터예요. 실제 포인트·기관 신청에는 영향을 주지 않아요.'
                : '기존 출석 지갑과 같은 실제 포인트예요. 사용과 보상은 서버에서 처리해요.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('확인'),
            ),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: PetColors.softShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Color(0xFFFFCE3B),
                shape: BoxShape.circle,
              ),
              child: Text('P', style: petText(18, color: Color(0xFF8A5B00))),
            ),
            const SizedBox(width: 6),
            if (pet.isPreview)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Text(
                  '예시',
                  style: petText(12, color: PetColors.secondary),
                ),
              ),
            Flexible(child: Text(petNumber(pet.points), style: petText(18))),
          ],
        ),
      ),
    ),
  );
}

class PetHeader extends StatelessWidget {
  const PetHeader(
    this.title, {
    super.key,
    this.pet,
    this.stage,
    this.trailing,
    this.back = true,
  });
  final String title;
  final PetPreviewController? pet;
  final String? stage;
  final Widget? trailing;
  final bool back;
  @override
  Widget build(BuildContext c) {
    final left = Row(
      children: [
        if (back)
          SizedBox(
            width: 40,
            height: 56,
            child: IconButton(
              tooltip: '이전',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 24),
              onPressed: () => Navigator.maybePop(c),
            ),
          ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(title, style: petText(25)),
              if (stage != null)
                PetPill(stage!, color: PetColors.blue, ink: Colors.white),
            ],
          ),
        ),
      ],
    );
    final right =
        trailing ?? (pet == null ? const SizedBox() : PetPoints(pet!));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (c, b) =>
            b.maxWidth < 320 || MediaQuery.textScalerOf(c).scale(1) > 1.4
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  Align(alignment: Alignment.centerRight, child: right),
                ],
              )
            : Row(
                children: [
                  Expanded(child: left),
                  const SizedBox(width: 8),
                  right,
                ],
              ),
      ),
    );
  }
}

class PetScreen extends StatelessWidget {
  const PetScreen({
    super.key,
    required this.child,
    this.colors = PetColors.skyGradient,
    this.footer,
    this.fullscreen = false,
    this.padding = 16,
  });
  final Widget child;
  final List<Color> colors;
  final Widget? footer;
  final bool fullscreen;
  final double padding;
  @override
  Widget build(BuildContext c) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
    ),
    child: Scaffold(
      backgroundColor: colors.last,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: SafeArea(
          top: fullscreen,
          bottom: fullscreen,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (c, b) => SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(padding, 0, padding, 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: b.maxHeight - 16),
                      child: child,
                    ),
                  ),
                ),
              ),
              if (footer != null)
                Padding(
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, 16),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PetPrimary extends StatelessWidget {
  const PetPrimary(
    this.label, {
    super.key,
    required this.onTap,
    this.color = PetColors.blue,
    this.light = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool light;
  final IconData? icon;
  @override
  Widget build(BuildContext c) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 58),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      foregroundColor: light ? color : Colors.white,
      backgroundColor: light ? const Color(0xFFEAF4FA) : color,
      shape: const StadiumBorder(),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(label, style: petText(20, color: light ? color : Colors.white)),
        if (icon != null) Icon(icon, size: 22),
      ],
    ),
  );
}

class PetSpeech extends StatelessWidget {
  const PetSpeech(this.text, {super.key, this.color = PetColors.green});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: PetColors.softShadow,
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: petText(19, color: color),
        ),
      ),
      CustomPaint(size: const Size(20, 8), painter: _TrianglePainter()),
    ],
  );
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) => c.drawPath(
    Path()
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close(),
    Paint()..color = Colors.white,
  );
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class PetPhoto extends StatelessWidget {
  const PetPhoto({
    super.key,
    required this.pet,
    this.height = 300,
    this.stage,
    this.view = 'angle',
    this.outfit,
    this.mood,
    this.silhouette = false,
  });
  final PetPreviewController pet;
  final double height;
  final int? stage;
  final String view;
  final Set<String>? outfit;
  final String? mood;
  final bool silhouette;
  @override
  Widget build(BuildContext c) {
    final s = stage ?? pet.stage;
    final folder = ['baby', 'junior', 'adult'][s];
    final clothes = outfit ?? pet.worn;
    final body = mood == 'greeting'
        ? 'assets/pet/$folder/greeting.png'
        : mood == 'hello' && s == 0
        ? 'assets/pet/motion/hello.gif'
        : mood == 'eating' && s == 0
        ? 'assets/pet/motion/eating.png'
        : mood == 'happy' && s == 0
        ? 'assets/pet/motion/happy.png'
        : 'assets/pet/$folder/$view.png';
    Widget image = Stack(
      fit: StackFit.expand,
      children: [
        if (view == 'angle' && mood == null)
          Image.asset(
            'assets/pet/$folder/angle_shadow.png',
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        Image.asset(body, fit: BoxFit.contain, excludeFromSemantics: true),
        for (final id in ['knit', 'winter', 'hat', 'flower'])
          if (mood == null && clothes.contains(id))
            if (id == 'winter')
              ColorFiltered(
                colorFilter: const ColorFilter.matrix([
                  .3,
                  .7,
                  0,
                  0,
                  0,
                  .2,
                  .4,
                  .1,
                  0,
                  0,
                  .3,
                  .5,
                  .3,
                  0,
                  0,
                  0,
                  0,
                  0,
                  1,
                  0,
                ]),
                child: Image.asset(
                  'assets/pet/$folder/knit_$view.png',
                  fit: BoxFit.contain,
                ),
              )
            else
              Image.asset(
                'assets/pet/$folder/${id}_$view.png',
                fit: BoxFit.contain,
              ),
      ],
    );
    if (silhouette) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        child: image,
      );
    }
    return Semantics(
      image: true,
      label: '${pet.name ?? '콩이'} ${['아기', '성장기', '성체'][s]}',
      child: SizedBox(height: height, width: double.infinity, child: image),
    );
  }
}

class PetStats extends StatelessWidget {
  const PetStats(this.pet, {super.key});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext c) => PetCard(
    padding: 16,
    child: LayoutBuilder(
      builder: (c, b) {
        final large =
            b.maxWidth < 300 || MediaQuery.textScalerOf(c).scale(1) > 1.35;
        final exp = pet.canGrow
            ? '가득!'
            : '${pet.experience}/${pet.nextExperience}';
        final fullness = [
          '배고파요',
          '배고파요',
          '괜찮아요',
          '괜찮아요',
          '든든해요',
          '배불러요',
        ][pet.fullness];
        Widget row(bool xp) {
          final label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              xp
                  ? Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: PetColors.lavender,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        'EXP',
                        style: petText(10, color: PetColors.purple),
                      ),
                    )
                  : const Icon(
                      Icons.ramen_dining_outlined,
                      color: PetColors.orange,
                      size: 24,
                    ),
              const SizedBox(width: 8),
              Text(xp ? '성장 경험치' : '배부름', style: petText(16)),
            ],
          );
          final bar = xp
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: pet.progress,
                    minHeight: 10,
                    color: const Color(0xFF8E7BFF),
                    backgroundColor: const Color(0xFFDDE8F1),
                  ),
                )
              : Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      Expanded(
                        child: Container(
                          height: 11,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: i < pet.fullness
                                ? const Color(0xFFFFB840)
                                : const Color(0xFFE0E8EE),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                  ],
                );
          if (large) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  children: [
                    label,
                    Text(
                      xp ? exp : fullness,
                      style: petText(16, color: PetColors.secondary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                bar,
              ],
            );
          }
          return Row(
            children: [
              SizedBox(width: 140, child: label),
              Expanded(child: bar),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: Text(
                  xp ? exp : fullness,
                  textAlign: TextAlign.right,
                  style: petText(
                    15,
                    color: xp && pet.canGrow
                        ? PetColors.purple
                        : PetColors.secondary,
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [row(true), const SizedBox(height: 18), row(false)],
        );
      },
    ),
  );
}

class FoodDrawing extends StatelessWidget {
  const FoodDrawing(this.id, {super.key, this.size = 48});
  final String id;
  final double size;
  @override
  Widget build(BuildContext c) =>
      CustomPaint(size: Size(size, size), painter: _FoodPainter(id));
}

class _FoodPainter extends CustomPainter {
  _FoodPainter(this.id);
  final String id;
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 64, s.height / 64);
    final p = Paint()..style = PaintingStyle.fill;
    if (id == 'food') {
      c.drawOval(
        const Rect.fromLTWH(5, 36, 54, 18),
        p..color = const Color(0xFF388CB9),
      );
      c.drawOval(
        const Rect.fromLTWH(5, 33, 54, 14),
        p..color = const Color(0xFFDFF0F8),
      );
      for (final a in [
        const Offset(23, 32),
        const Offset(32, 28),
        const Offset(40, 34),
      ]) {
        c.drawOval(
          Rect.fromCenter(center: a, width: 10, height: 15),
          p..color = const Color(0xFFB87A35),
        );
      }
    } else if (id == 'sweet') {
      c.save();
      c.translate(30, 35);
      c.rotate(.55);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 43, height: 27),
        p..color = const Color(0xFFA957A7),
      );
      c.drawArc(
        const Rect.fromLTWH(-14, -8, 26, 17),
        3.4,
        2.0,
        false,
        p
          ..color = const Color(0xFFF6CE7C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6,
      );
      c.restore();
      p.style = PaintingStyle.fill;
      c.drawLine(
        const Offset(44, 20),
        const Offset(47, 7),
        p
          ..color = const Color(0xFF59A75C)
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round,
      );
      c.drawLine(const Offset(46, 18), const Offset(55, 10), p);
    } else if (id == 'gum') {
      c.save();
      c.translate(32, 32);
      c.rotate(-.55);
      p
        ..color = const Color(0xFFEAD5AD)
        ..style = PaintingStyle.fill;
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-18, -7, 36, 14),
          const Radius.circular(6),
        ),
        p,
      );
      for (final a in [
        const Offset(-20, -7),
        const Offset(-20, 7),
        const Offset(20, -7),
        const Offset(20, 7),
      ]) {
        c.drawCircle(a, 9, p);
        c.drawCircle(a, 6, p..color = const Color(0xFFFFF7E5));
        p.color = const Color(0xFFEAD5AD);
      }
      c.restore();
    } else {
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 29, 40, 25),
          const Radius.circular(8),
        ),
        p..color = const Color(0xFFFFCE8B),
      );
      c.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(12, 28, 40, 13),
          const Radius.circular(8),
        ),
        p..color = const Color(0xFFFF89B6),
      );
      c.drawLine(
        const Offset(32, 25),
        const Offset(32, 13),
        p
          ..color = const Color(0xFF7CC9AE)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
      c.drawOval(
        const Rect.fromLTWH(29, 3, 6, 10),
        p..color = const Color(0xFFFFAE26),
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_FoodPainter old) => old.id != id;
}

class PetRays extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final center = Offset(s.width / 2, s.height * .34);
    final radius = s.height;
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFE8A2).withValues(alpha: .75),
          const Color(0xFFFFE8A2).withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * .7));
    for (var i = 0; i < 24; i++) {
      final a = i * math.pi / 12;
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(
          center.dx + math.cos(a) * radius,
          center.dy + math.sin(a) * radius,
        )
        ..lineTo(
          center.dx + math.cos(a + .12) * radius,
          center.dy + math.sin(a + .12) * radius,
        )
        ..close();
      c.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

Future<bool> petDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? emblem,
  List<(String, String)> rows = const [],
  String action = '확인',
  String? secondary,
  Color color = PetColors.blue,
}) async =>
    await showDialog<bool>(
      context: petModalContext(context),
      useRootNavigator: false,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        backgroundColor: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (emblem != null) ...[
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: emblem,
                  ),
                ),
                const SizedBox(height: 22),
              ],
              Text(title, textAlign: TextAlign.center, style: petText(25)),
              if (message != null) ...[
                const SizedBox(height: 14),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: petText(
                    18,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
              ],
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 22),
                PetCard(
                  color: const Color(0xFFF5F8FB),
                  padding: 16,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Divider(height: 1, color: PetColors.line),
                          ),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          runSpacing: 6,
                          spacing: 12,
                          children: [
                            Text(
                              rows[i].$1,
                              style: petText(17, color: PetColors.secondary),
                            ),
                            Text(
                              rows[i].$2,
                              style: petText(
                                20,
                                color: i == rows.length - 1
                                    ? color
                                    : PetColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              PetPrimary(
                action,
                color: color,
                onTap: () => Navigator.pop(c, true),
              ),
              if (secondary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: Text(
                      secondary,
                      style: petText(18, color: PetColors.secondary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ) ??
    false;

/// Outline symbols from the supplied mockup, drawn as native vectors.
class PetLineIcon extends StatelessWidget {
  const PetLineIcon(
    this.icon, {
    super.key,
    this.color = PetColors.blue,
    this.size = 28,
  });
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext c) =>
      [
        Icons.ramen_dining_outlined,
        Icons.checkroom_outlined,
        Icons.bar_chart,
      ].contains(icon)
      ? Center(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: _PetSymbol(icon, color)),
          ),
        )
      : Icon(icon, color: color, size: size);
}

class _PetSymbol extends CustomPainter {
  _PetSymbol(this.icon, this.color);
  final IconData icon;
  final Color color;
  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.scale(s.width / 48, s.height / 48);
    final p = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (icon == Icons.checkroom_outlined) {
      c.drawPath(
        Path()
          ..moveTo(17, 6)
          ..lineTo(8, 10)
          ..lineTo(3, 19)
          ..lineTo(12, 23)
          ..lineTo(14, 17)
          ..lineTo(14, 42)
          ..lineTo(34, 42)
          ..lineTo(34, 17)
          ..lineTo(36, 23)
          ..lineTo(45, 19)
          ..lineTo(40, 10)
          ..lineTo(31, 6)
          ..quadraticBezierTo(24, 17, 17, 6)
          ..close(),
        p,
      );
    } else if (icon == Icons.ramen_dining_outlined) {
      c.drawPath(
        Path()
          ..moveTo(7, 24)
          ..lineTo(41, 24)
          ..quadraticBezierTo(39, 41, 24, 41)
          ..quadraticBezierTo(9, 41, 7, 24)
          ..close(),
        p,
      );
      c.drawPath(
        Path()
          ..moveTo(19, 17)
          ..cubicTo(16, 12, 23, 11, 21, 5)
          ..moveTo(30, 17)
          ..cubicTo(27, 12, 34, 11, 32, 5),
        p,
      );
    } else {
      c.drawPath(
        Path()
          ..moveTo(6, 6)
          ..lineTo(6, 42)
          ..lineTo(43, 42)
          ..moveTo(17, 39)
          ..lineTo(17, 28)
          ..moveTo(27, 39)
          ..lineTo(27, 13)
          ..moveTo(37, 39)
          ..lineTo(37, 23),
        p,
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_PetSymbol old) => old.icon != icon || old.color != color;
}

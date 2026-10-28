import 'package:flutter/material.dart';

import '../attendance/attendance_controller.dart';
import '../attendance/attendance_dialog.dart';
import '../pet/pet_design.dart';
import '../pet/pet_preview_controller.dart';
import 'activity_hub_widgets.dart';

class ActivityPetScope extends InheritedNotifier<PetPreviewController> {
  const ActivityPetScope({
    super.key,
    required PetPreviewController pet,
    required super.child,
    this.onOpenPet,
  }) : super(notifier: pet);
  final VoidCallback? onOpenPet;
  static VoidCallback? openPetOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<ActivityPetScope>()?.onOpenPet;
  static PetPreviewController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActivityPetScope>()?.notifier;
}

abstract final class ActivityColors {
  static const blue = Color(0xFF0878B4),
      sky = Color(0xFFD5EAFA),
      mint = Color(0xFFD7F1E4),
      orange = Color(0xFFFFE8CE),
      pink = Color(0xFFFADDEB),
      green = Color(0xFF258754),
      muted = Color(0xFF6D8091),
      background = Color(0xFFF2F7FB);
}

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({
    super.key,
    required this.title,
    required this.child,
    this.tint = ActivityColors.sky,
    this.bottom,
    this.trailing,
    this.wallet = true,
    this.processing = false,
  });
  final String title;
  final Widget child;
  final Color tint;
  final Widget? bottom, trailing;
  final bool wallet;
  final bool processing;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ActivityColors.background,
    body: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, .65],
                colors: [tint, ActivityColors.background],
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        shadowColor: const Color(0x22263B50),
                        child: IconButton(
                          tooltip: '뒤로',
                          onPressed: () => Navigator.maybePop(context),
                          icon: const Icon(
                            Icons.chevron_left_rounded,
                            size: 32,
                            color: PetColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          style: petText(25, weight: FontWeight.w800),
                        ),
                      ),
                      if (trailing != null)
                        trailing!
                      else if (wallet)
                        ActivityWalletPill(
                          balance: AttendanceScope.maybeOf(context)
                              ?.status
                              ?.balance,
                          onTap: () async {
                            final attendance = AttendanceScope.maybeOf(context);
                            final pet = ActivityPetScope.maybeOf(context);
                            if (attendance != null) {
                              await showAttendanceDialog(context, attendance);
                            }
                            if (pet != null) await pet.load();
                          },
                        ),
                    ],
                  ),
                ),
                Expanded(child: child),
                if (bottom != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: bottom!,
                  ),
              ],
            ),
          ),
        ),
        if (processing)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x88142230),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: ActivityCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 20),
                        Text(
                          '처리하고 있어요',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          '잠시만 기다려 주세요.\n화면을 닫지 말아 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            color: PetColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class ActivityCard extends StatelessWidget {
  const ActivityCard({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = 18,
    this.border,
    this.onTap,
  });
  final Widget child;
  final Color color;
  final double padding;
  final BorderSide? border;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x1424374B),
          blurRadius: 20,
          offset: Offset(0, 9),
        ),
      ],
    ),
    child: Material(
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: border ?? BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: EdgeInsets.all(padding), child: child),
      ),
    ),
  );
}

class ActivityButton extends StatelessWidget {
  const ActivityButton(
    this.label, {
    super.key,
    required this.onTap,
    this.light = false,
    this.color = ActivityColors.blue,
    this.icon,
  });
  final String label;
  final VoidCallback? onTap;
  final bool light;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 54),
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        backgroundColor: light ? const Color(0xFFE0EFFA) : color,
        foregroundColor: light ? ActivityColors.blue : Colors.white,
        disabledBackgroundColor: const Color(0xFFDCE5ED),
        shape: const StadiumBorder(),
        elevation: light ? 0 : 3,
        shadowColor: const Color(0x44236C91),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          if (icon != null) Icon(icon, size: 21),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

class ActivityChoices<T> extends StatelessWidget {
  const ActivityChoices({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.describe,
    this.icons,
  });
  final List<T> values;
  final bool Function(T) selected;
  final ValueChanged<T> onSelect;
  final String Function(T)? describe;
  final Map<T, IconData>? icons;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        Semantics(
          selected: selected(value),
          button: true,
          child: Material(
            color: selected(value)
                ? ActivityColors.blue
                : const Color(0xFFF4F8FB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
              side: BorderSide(
                color: selected(value)
                    ? ActivityColors.blue
                    : const Color(0xFFE1EAF1),
                width: 1.5,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => onSelect(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icons?[value] != null)
                      Icon(
                        icons![value],
                        color: selected(value)
                            ? Colors.white
                            : ActivityColors.muted,
                      ),
                    Text(
                      describe?.call(value) ?? '$value',
                      style: petText(
                        16,
                        color: selected(value)
                            ? Colors.white
                            : PetColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class ActivityHeading extends StatelessWidget {
  const ActivityHeading(
    this.title, {
    super.key,
    this.color = ActivityColors.blue,
    this.trailing,
  });
  final String title;
  final Color color;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 21,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: petText(21, weight: FontWeight.w800)),
        ),
        ?trailing,
      ],
    ),
  );
}

class ActivityEmpty extends StatelessWidget {
  const ActivityEmpty(
    this.title, {
    super.key,
    required this.message,
    this.icon = Icons.search,
    this.action,
    this.onAction,
    this.secondary,
    this.onSecondary,
    this.error = false,
  });
  final String title, message;
  final IconData icon;
  final String? action, secondary;
  final VoidCallback? onAction, onSecondary;
  final bool error;
  @override
  Widget build(BuildContext context) => ActivityCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: error ? const Color(0xFFFFECEC) : const Color(0xFFEAF5FC),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 36,
              color: error ? Colors.redAccent : ActivityColors.blue,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: petText(21)),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: petText(
            16,
            color: PetColors.secondary,
            weight: FontWeight.w500,
          ),
        ),
        if (action != null) ...[
          const SizedBox(height: 18),
          ActivityButton(action!, onTap: onAction),
        ],
        if (secondary != null) ...[
          const SizedBox(height: 8),
          ActivityButton(secondary!, onTap: onSecondary, light: true),
        ],
        const SizedBox(height: 8),
      ],
    ),
  );
}

class ActivitySkeleton extends StatelessWidget {
  const ActivitySkeleton({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '프로그램을 불러오고 있어요',
    child: Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ActivityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final width in [90.0, 220.0, 160.0, 190.0])
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      width: width,
                      height: 15,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF2F7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

Future<bool> activityDialog(
  BuildContext context, {
  required String title,
  required String message,
  String action = '확인',
  String secondary = '취소',
  IconData icon = Icons.confirmation_number_outlined,
  Color color = ActivityColors.blue,
  List<(String, String)> rows = const [],
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, size: 38, color: color),
                ),
              ),
              const SizedBox(height: 20),
              Text(title, textAlign: TextAlign.center, style: petText(23)),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: petText(
                  17,
                  color: PetColors.secondary,
                  weight: FontWeight.w500,
                ),
              ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 18),
                ActivityCard(
                  color: const Color(0xFFF3F7FB),
                  padding: 14,
                  child: Column(
                    children: [
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  row.$1,
                                  style: petText(
                                    15,
                                    color: PetColors.secondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  row.$2,
                                  textAlign: TextAlign.end,
                                  style: petText(16),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              ActivityButton(
                action,
                color: color,
                onTap: () => Navigator.pop(c, true),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(
                  secondary,
                  style: petText(17, color: PetColors.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;

Future<void> activityFailure(
  BuildContext context, {
  required String title,
  String message = '인터넷 연결을 확인한 뒤 다시 시도해 주세요. 처리 상태를 먼저 확인하면 중복 신청을 막을 수 있어요.',
  VoidCallback? onRetry,
}) async {
  final retry = await activityDialog(
    context,
    title: title,
    message: message,
    icon: Icons.wifi_off_rounded,
    color: Colors.redAccent,
    action: onRetry == null ? '확인' : '다시 시도',
    secondary: '닫기',
  );
  if (retry && context.mounted) onRetry?.call();
}

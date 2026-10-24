import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'attendance_controller.dart';
import 'attendance_dialog.dart';

/// "🪙 125 P" shown at the top right of each tab. Tapping reopens the
/// attendance popup. Hidden outside [AttendanceScope] or until the first
/// status arrives, so screens opened on their own keep their old header.
class PointBadge extends StatelessWidget {
  const PointBadge({super.key, this.onDark = false});

  /// Home's blue header: white pill instead of the light blue one.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final controller = AttendanceScope.maybeOf(context);
    final status = controller?.status;
    if (controller == null || status == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: '보유 포인트 ${status.balance}포인트, 출석체크 열기',
      excludeSemantics: true,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: onDark ? AppColors.surface : AppColors.tint,
          foregroundColor: AppColors.blueText,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        onPressed: () => showAttendanceDialog(context, controller),
        child: Text('🪙 ${status.balance} P'),
      ),
    );
  }
}

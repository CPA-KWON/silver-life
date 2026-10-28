import 'package:flutter/material.dart';

import '../activity/activity_hub_widgets.dart' show ActivityWalletPill;
import 'attendance_controller.dart';
import 'attendance_dialog.dart';

/// Shared star wallet pill. Opens the existing attendance/calendar flow and
/// always displays the actual server balance, including on nested pages.
class PointBadge extends StatelessWidget {
  const PointBadge({super.key, this.onDark = false});
  final bool onDark; // Kept for callers using the previous header API.
  @override
  Widget build(BuildContext context) {
    final controller = AttendanceScope.maybeOf(context),
        status = AttendanceScope.maybeOf(context)?.status;
    if (controller == null || status == null) return const SizedBox.shrink();
    return ActivityWalletPill(
      balance: status.balance,
      onTap: () {
        showAttendanceDialog(context, controller);
      },
    );
  }
}

import 'package:flutter/widgets.dart';

import 'attendance_repository.dart';

/// Holds the signed-in user's attendance/point status so the point badges on
/// every tab and the attendance popup show the same, instantly updated value.
class AttendanceController extends ChangeNotifier {
  AttendanceController({AttendanceRepository? repository})
    : repository = repository ?? AttendanceRepository();

  final AttendanceRepository repository;
  AttendanceStatus? status;

  /// Returns null (keeping the last known status) when the server is
  /// unreachable or the attendance SQL is not installed yet.
  Future<AttendanceStatus?> refresh() async {
    try {
      final next = await repository.status();
      status = next;
      notifyListeners();
      return next;
    } catch (_) {
      return null;
    }
  }

  /// Throws on network/server errors; callers then [refresh] to learn whether
  /// the server actually recorded today's attendance.
  Future<AttendanceCheckInResult> checkIn() async {
    final result = await repository.checkIn();
    status = result.status;
    notifyListeners();
    return result;
  }
}

/// Makes the [AttendanceController] of [MainShell] available to its tabs.
class AttendanceScope extends InheritedNotifier<AttendanceController> {
  const AttendanceScope({
    super.key,
    required AttendanceController controller,
    required super.child,
  }) : super(notifier: controller);

  static AttendanceController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AttendanceScope>()?.notifier;
}

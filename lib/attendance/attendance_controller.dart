import 'package:flutter/widgets.dart';

import 'attendance_repository.dart';

/// Holds the signed-in user's attendance/point status so the point badges on
/// every tab and the attendance popup show the same, instantly updated value.
class AttendanceController extends ChangeNotifier {
  AttendanceController({AttendanceRepository? repository})
    : repository = repository ?? AttendanceRepository();

  final AttendanceRepository repository;
  AttendanceStatus? status;
    /// 출석 창의 "포인트 사용하러 가기" 버튼이 부르는 동작이에요. 앱 홈에서 연결해요.
  VoidCallback? onUsePoints;
  bool _disposed = false;
  Future<AttendanceStatus?>? _refreshing;
  int _revision = 0;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Returns null (keeping the last known status) when the server is
  /// unreachable or the attendance SQL is not installed yet.
  Future<AttendanceStatus?> refresh() {
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<AttendanceStatus?> _refresh() async {
    final revision = _revision;
    try {
      final next = await repository.status();
      // A status request started before a successful stamp must not undo it.
      if (!_disposed && revision == _revision) {
        status = next;
        notifyListeners();
      }
      return status;
    } catch (_) {
      return null;
    }
  }

  /// Throws on network/server errors; callers then [refresh] to learn whether
  /// the server actually recorded today's attendance.
  Future<AttendanceCheckInResult> checkIn() async {
    final result = await repository.checkIn();
    _revision++;
    status = result.status;
    if (!_disposed) notifyListeners();
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

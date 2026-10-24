import 'dart:async';

import 'package:silver_life/attendance/attendance_repository.dart';

enum FakeCheckInFailure { none, beforeServer, afterServer }

/// In-memory copy of supabase/attendance_points.sql rules for widget tests.
class FakeAttendanceRepository extends AttendanceRepository {
  FakeAttendanceRepository({DateTime? today, this.failStatus = false})
    : today = today ?? DateTime(2026, 10, 24);

  DateTime today;
  bool failStatus;
  FakeCheckInFailure failure = FakeCheckInFailure.none;
  int balance = 0;
  int total = 0;
  int streak = 0;
  DateTime? last;
  final days = <AttendanceDay>[];
  int checkInCalls = 0;
  int paidCount = 0;

  /// Keeps a check-in pending so tests can tap repeatedly mid-request.
  Completer<void>? gate;

  /// Pretends the user stamped every day up to yesterday for [count] days.
  void attendedBefore(int count) {
    for (var i = count; i >= 1; i--) {
      final day = today.subtract(Duration(days: i));
      final s = count - i + 1;
      final p = _points(s);
      days.add(AttendanceDay(date: day, streak: s, points: p));
      balance += p;
      total += p;
    }
    streak = count;
    last = today.subtract(const Duration(days: 1));
  }

  int _points(int s) => switch (s) {
    30 => 10,
    14 => 5,
    7 => 3,
    _ => 1,
  };

  AttendanceStatus get _status => AttendanceStatus(
    today: today,
    attendedToday: last == today,
    streak:
        last != null && !last!.isBefore(today.subtract(const Duration(days: 1)))
        ? streak
        : 0,
    balance: balance,
    totalEarned: total,
    todayPoints: last == today ? days.last.points : null,
  );

  @override
  Future<AttendanceStatus> status() async {
    if (failStatus) throw Exception('offline');
    return _status;
  }

  @override
  Future<AttendanceCheckInResult> checkIn() async {
    checkInCalls++;
    if (gate != null) await gate!.future;
    if (failure == FakeCheckInFailure.beforeServer) throw Exception('offline');
    if (last == today) {
      return AttendanceCheckInResult(status: _status, already: true);
    }
    streak = last == today.subtract(const Duration(days: 1)) ? streak + 1 : 1;
    final p = _points(streak);
    days.add(AttendanceDay(date: today, streak: streak, points: p));
    balance += p;
    total += p;
    last = today;
    paidCount++;
    if (failure == FakeCheckInFailure.afterServer) throw Exception('timeout');
    return AttendanceCheckInResult(status: _status, already: false, points: p);
  }

  @override
  Future<List<AttendanceDay>> month(DateTime month) async => days
      .where((d) => d.date.year == month.year && d.date.month == month.month)
      .toList();
}

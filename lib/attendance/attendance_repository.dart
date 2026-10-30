import '../core/points.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Streak day → total points paid that day (see supabase/attendance_points.sql).
const attendanceBasePoints = 5;
const attendanceMilestonePoints = {7: 15, 14: 25, 30: 50};
final attendanceMilestones = attendanceMilestonePoints.keys.toSet();

/// The attendance date is the KST calendar date decided by the server
/// (`attendance_today()`), so it is kept as a plain date without a time zone.
DateTime _date(dynamic value) {
  final d = DateTime.parse('$value');
  return DateTime(d.year, d.month, d.day);
}

class AttendanceStatus {
  const AttendanceStatus({
    required this.today,
    required this.attendedToday,
    required this.streak,
    required this.balance,
    required this.totalEarned,
    this.todayPoints,
  });

  factory AttendanceStatus.fromJson(Map<String, dynamic> json) =>
      AttendanceStatus(
        today: _date(json['today']),
        attendedToday: json['attended_today'] as bool? ?? false,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        totalEarned: (json['total_earned'] as num?)?.toInt() ?? 0,
        todayPoints: (json['today_points'] as num?)?.toInt(),
      );

  final DateTime today;
  final bool attendedToday;
  final int streak;
  final int balance;
  final int totalEarned;
  final int? todayPoints;
}

class AttendanceCheckInResult {
  const AttendanceCheckInResult({
    required this.status,
    required this.already,
    this.points,
  });
  final AttendanceStatus status;

  /// True when today was already recorded (another tap or another device).
  final bool already;
  final int? points;
}

class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.streak,
    required this.points,
  });
  final DateTime date;
  final int streak;
  final int points;
  bool get isMilestone => attendanceMilestones.contains(streak);
}

/// Success text shown after a stamp, by the streak the server returned.
String attendanceRewardMessage(int streak, int points) =>
    attendanceMilestones.contains(streak)
    ? '🎉 $streak일 연속 출석 달성! ${pointAmount(points)}포인트 획득!'
    : '출석 완료! ${pointAmount(points)}포인트를 획득했어요!';

/// A future day that pays a streak reward if the user stamps every day.
class UpcomingMilestone {
  const UpcomingMilestone({
    required this.date,
    required this.streak,
    required this.stampsNeeded,
  });
  final DateTime date;
  final int streak;

  /// Stamps still needed, counting today (if not stamped yet) and [date].
  final int stampsNeeded;
  int get points => attendanceMilestonePoints[streak]!;
}

/// Milestone days still ahead of the current streak, nearest first.
List<UpcomingMilestone> upcomingMilestones(AttendanceStatus status) {
  // Streak the next stamp would reach: today's if not stamped yet,
  // otherwise tomorrow's.
  final firstDay = status.attendedToday ? 1 : 0;
  final nextStreak = status.streak + 1;
  return [
    for (final m in attendanceMilestones.toList()..sort())
      if (m >= nextStreak)
        UpcomingMilestone(
          date: DateTime(
            status.today.year,
            status.today.month,
            status.today.day + firstDay + (m - nextStreak),
          ),
          streak: m,
          stampsNeeded: m - nextStreak + 1,
        ),
  ];
}

class AttendanceRepository {
  AttendanceRepository({this._client});
  final SupabaseClient? _client;
  SupabaseClient get client => _client ?? Supabase.instance.client;

  Future<AttendanceStatus> status() async => AttendanceStatus.fromJson(
    Map<String, dynamic>.from(await client.rpc('attendance_status') as Map),
  );

  /// Server decides the date, streak and points in one transaction and pays
  /// at most once per day, so repeated calls are safe.
  Future<AttendanceCheckInResult> checkIn() async {
    final json = Map<String, dynamic>.from(
      await client.rpc('attendance_check_in') as Map,
    );
    return AttendanceCheckInResult(
      status: AttendanceStatus.fromJson(json),
      already: json['already'] as bool? ?? false,
      points: (json['points'] as num?)?.toInt(),
    );
  }

  /// Attendance records of one calendar month (RLS returns only the user's).
  Future<List<AttendanceDay>> month(DateTime month) async {
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final rows = await client
        .from('attendance_days')
        .select('attended_on,streak,points')
        .eq('user_id', client.auth.currentUser!.id)
        .gte('attended_on', day(DateTime(month.year, month.month)))
        .lt('attended_on', day(DateTime(month.year, month.month + 1)))
        .order('attended_on');
    return [
      for (final r in rows)
        AttendanceDay(
          date: _date(r['attended_on']),
          streak: (r['streak'] as num).toInt(),
          points: (r['points'] as num).toInt(),
        ),
    ];
  }

  /// A Monday–Sunday strip can span two months. Read both using the existing
  /// self-only attendance table; never infer missed/attended days from streak.
  Future<List<AttendanceDay>> week(DateTime today) async {
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    final months = await Future.wait([
      month(monday),
      if (monday.month != sunday.month || monday.year != sunday.year)
        month(sunday),
    ]);
    return months
        .expand((v) => v)
        .where((d) => !d.date.isBefore(monday) && !d.date.isAfter(sunday))
        .toList();
  }
}

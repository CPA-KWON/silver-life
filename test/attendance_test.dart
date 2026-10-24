import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/attendance/attendance_dialog.dart';
import 'package:silver_life/attendance/attendance_repository.dart';
import 'package:silver_life/home/main_shell.dart';

import 'support/fake_activity_repository.dart';
import 'support/fake_attendance_repository.dart';
import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> shell(WidgetTester t, FakeAttendanceRepository repo) => mount(
    t,
    MainShell(
      activityRepository: FakeActivityRepository(),
      attendanceRepository: repo,
      facilityPage: const ColoredBox(color: Colors.blue),
    ),
  );

  test('reward message replaces base points on milestone days', () {
    expect(attendanceRewardMessage(1, 1), '출석 완료! 1포인트를 획득했어요!');
    expect(attendanceRewardMessage(7, 3), '🎉 7일 연속 출석 달성! 3포인트 획득!');
    expect(attendanceRewardMessage(14, 5), '🎉 14일 연속 출석 달성! 5포인트 획득!');
    expect(attendanceRewardMessage(30, 10), '🎉 30일 연속 출석 달성! 10포인트 획득!');
    expect(attendanceRewardMessage(31, 1), '출석 완료! 1포인트를 획득했어요!');
  });

  test('upcoming milestones count today only before it is stamped', () {
    AttendanceStatus status(int streak, bool attendedToday) => AttendanceStatus(
      today: DateTime(2026, 10, 24),
      attendedToday: attendedToday,
      streak: streak,
      balance: 0,
      totalEarned: 0,
    );
    final fresh = upcomingMilestones(status(0, false));
    expect(fresh.map((u) => u.date), [
      DateTime(2026, 10, 30),
      DateTime(2026, 11, 6),
      DateTime(2026, 11, 22),
    ]);
    expect(fresh.first.stampsNeeded, 7);
    final stamped = upcomingMilestones(status(3, true)).first;
    expect(stamped.date, DateTime(2026, 10, 28));
    expect(stamped.stampsNeeded, 4);
    final dueToday = upcomingMilestones(status(6, false)).first;
    expect(dueToday.date, DateTime(2026, 10, 24));
    expect(dueToday.stampsNeeded, 1);
    expect(upcomingMilestones(status(30, true)), isEmpty);
  });

  testWidgets('calendar previews the next star day faintly with a hint', (
    t,
  ) async {
    final repo = FakeAttendanceRepository()..attendedBefore(4);
    await shell(t, repo);
    expect(
      find.text('앞으로 3번 더 출석하면 10월 26일에 ⭐ 7일 연속 달성! (3포인트)'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('26일, 계속 출석하면 7일 연속 달성 예정'), findsOneWidget);
    await tap(t, find.text('출석도장 찍기'));
    expect(
      find.text('앞으로 2번 더 출석하면 10월 26일에 ⭐ 7일 연속 달성! (3포인트)'),
      findsOneWidget,
    );
    await tap(t, find.text('다음 달 ›'));
    expect(find.bySemanticsLabel('2일, 계속 출석하면 14일 연속 달성 예정'), findsOneWidget);
    await finish(t);
  });

  testWidgets('popup opens on launch and closing it records nothing', (
    t,
  ) async {
    final repo = FakeAttendanceRepository();
    await shell(t, repo);
    expect(find.text('매일매일 출석체크'), findsOneWidget);
    expect(find.text('2026년 10월'), findsOneWidget);
    await tap(t, find.text('닫기'));
    expect(find.text('매일매일 출석체크'), findsNothing);
    expect(repo.checkInCalls, 0);
    expect(find.text('🪙 0 P'), findsOneWidget);
    // Next app start (same day, still not stamped) asks again.
    await finish(t);
    await shell(t, repo);
    expect(find.text('매일매일 출석체크'), findsOneWidget);
    await finish(t);
  });

  testWidgets('stamp pays once even with rapid taps and updates the badge', (
    t,
  ) async {
    final repo = FakeAttendanceRepository()..gate = Completer<void>();
    await shell(t, repo);
    await t.ensureVisible(find.text('출석도장 찍기'));
    await t.pumpAndSettle();
    await t.tap(find.text('출석도장 찍기'));
    await t.pump();
    await t.tap(find.byType(FilledButton).first, warnIfMissed: false);
    await t.pump();
    repo.gate!.complete();
    await t.pumpAndSettle();
    expect(repo.checkInCalls, 1);
    expect(repo.paidCount, 1);
    expect(find.text('출석 완료! 1포인트를 획득했어요!'), findsOneWidget);
    expect(find.text('오늘 출석 완료!'), findsOneWidget);
    final button = t.widget<FilledButton>(
      find.ancestor(
        of: find.text('오늘 출석 완료!'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('🔥 1일 연속 출석 달성!'), findsOneWidget);
    await tap(t, find.text('닫기'));
    expect(find.text('🪙 1 P'), findsOneWidget);
    await finish(t);
  });

  testWidgets('seventh straight day shows the milestone reward and star', (
    t,
  ) async {
    final repo = FakeAttendanceRepository()..attendedBefore(6);
    await shell(t, repo);
    expect(find.text('🔥 6일 연속 출석 달성!'), findsOneWidget);
    expect(find.text('오늘 출석하면 ⭐ 7일 연속 달성! (3포인트)'), findsOneWidget);
    await tap(t, find.text('출석도장 찍기'));
    expect(find.text('🎉 7일 연속 출석 달성! 3포인트 획득!'), findsOneWidget);
    expect(
      find.text('앞으로 7번 더 출석하면 10월 31일에 ⭐ 14일 연속 달성! (5포인트)'),
      findsOneWidget,
    );
    expect(find.text('보유 포인트  🪙 9 P'), findsOneWidget);
    expect(find.bySemanticsLabel('오늘, 24일 출석, 7일 연속 달성'), findsOneWidget);
    expect(find.bySemanticsLabel('18일 출석'), findsOneWidget);
    await finish(t);
  });

  testWidgets('already stamped today: no auto popup, badge reopens status', (
    t,
  ) async {
    final repo = FakeAttendanceRepository()..attendedBefore(2);
    await repo.checkIn();
    await shell(t, repo);
    expect(find.text('매일매일 출석체크'), findsNothing);
    await tap(t, find.text('🪙 3 P').first);
    expect(find.text('매일매일 출석체크'), findsOneWidget);
    expect(find.text('오늘 출석 완료!'), findsOneWidget);
    await tap(t, find.text('‹ 이전 달'));
    expect(find.text('2026년 9월'), findsOneWidget);
    await tap(t, find.text('다음 달 ›'));
    await tap(t, find.text('다음 달 ›'));
    expect(find.text('2026년 11월'), findsOneWidget);
    await finish(t);
  });

  testWidgets('network error asks the server what really happened', (t) async {
    final repo = FakeAttendanceRepository()
      ..failure = FakeCheckInFailure.beforeServer;
    await shell(t, repo);
    await tap(t, find.text('출석도장 찍기'));
    expect(
      find.text('출석을 처리하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.'),
      findsOneWidget,
    );
    expect(find.text('출석도장 찍기'), findsOneWidget);
    repo.failure = FakeCheckInFailure.afterServer;
    await tap(t, find.text('출석도장 찍기'));
    expect(find.text('연결이 잠시 끊겼지만 오늘 출석은 정상 처리됐어요. (1포인트)'), findsOneWidget);
    expect(find.text('오늘 출석 완료!'), findsOneWidget);
    expect(repo.paidCount, 1);
    await finish(t);
  });

  testWidgets('attendance setup missing keeps the shell unchanged', (t) async {
    await shell(t, FakeAttendanceRepository(failStatus: true));
    expect(find.text('매일매일 출석체크'), findsNothing);
    expect(find.textContaining(' P'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    await finish(t);
  });

  testWidgets('calendar fits a narrow phone with enlarged text', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = FakeAttendanceRepository()..attendedBefore(14);
    await mount(
      t,
      MainShell(
        activityRepository: FakeActivityRepository(),
        attendanceRepository: repo,
        facilityPage: const ColoredBox(color: Colors.blue),
      ),
      scale: 1.3,
    );
    expect(find.byType(AttendanceDialog), findsOneWidget);
    await tap(t, find.text('출석도장 찍기'));
    expect(find.text('출석 완료! 1포인트를 획득했어요!'), findsOneWidget);
    expect(t.takeException(), isNull);
    await finish(t);
  });
}

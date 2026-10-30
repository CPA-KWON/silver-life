import 'package:silver_life/attendance/attendance_dialog.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/attendance/attendance_controller.dart';
import 'package:silver_life/attendance/attendance_repository.dart';
import 'package:silver_life/home/home_tab.dart';
import 'package:silver_life/home/home_widgets.dart';
import 'package:silver_life/home/main_shell.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/pet/pet_repository.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';
import 'support/fake_attendance_repository.dart';
import 'support/widget_actions.dart';

class WeekRepository extends FakeAttendanceRepository {
  WeekRepository({super.today});
  final requestedMonths = <int>[];
  bool failWeek = false;
  @override
  Future<List<AttendanceDay>> month(DateTime month) async {
    requestedMonths.add(month.month);
    if (failWeek) throw StateError('offline');
    return super.month(month);
  }
}

class PetAttendanceRepository extends PetRepository {
  PetAttendanceRepository(this.attendance);
  final FakeAttendanceRepository attendance;
  int experience = 0;
  Completer<void>? loadGate;
  @override
  Future<PetJson> load() async {
    if (loadGate != null) await loadGate!.future;
    return {
      'today': attendance.today.toIso8601String(),
      'pet': {
        'name': '콩이',
        'stage': 0,
        'experience': experience,
        'fullness': 2,
        'adopted_at': attendance.today.toIso8601String(),
      },
      'balance': attendance.balance,
      'attended': attendance.last == attendance.today,
      'history': [
        if (experience > 0)
          {
            'title': '오늘 출석했어요',
            'kind': 'attendance',
            'created_at': attendance.today.toIso8601String(),
            'points': 0,
            'experience': 10,
          },
      ],
    };
  }

  @override
  Future<PetJson> act(String action, PetJson payload, String request) async {
    if (action != 'attendance') throw StateError('unexpected action');
    await attendance.checkIn();
    experience = 10;
    return {
      'state': await load(),
      'outcome': {'points': 0, 'experience': 10},
    };
  }
}

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<AttendanceController> controller(FakeAttendanceRepository repo) async {
    final c = AttendanceController(repository: repo);
    await c.refresh();
    addTearDown(c.dispose);
    return c;
  }

  Future<void> card(
    WidgetTester t,
    AttendanceController c, {
    Future<void> Function()? onStamped,
  }) => mount(
    t,
    AttendanceScope(
      controller: c,
      child: HomeAttendanceCard(onCalendar: () {}, onStamped: onStamped),
    ),
  );

  test('week reads both months at a calendar boundary', () async {
    final r = WeekRepository(today: DateTime(2026, 11, 1));
    for (final d in [
      DateTime(2026, 10, 25),
      DateTime(2026, 10, 31),
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 2),
    ]) {
      r.days.add(AttendanceDay(date: d, streak: 1, points: 1));
    }
    final week = await r.week(r.today);
    expect(r.requestedMonths, [10, 11]);
    expect(week.map((d) => d.date), [
      DateTime(2026, 10, 31),
      DateTime(2026, 11, 1),
    ]);
  });
  testWidgets(
    'weekly paw stamps use records with gaps rather than inferred streak',
    (t) async {
      final r = WeekRepository(today: DateTime(2026, 10, 25));
      for (final day in [19, 20, 23, 25]) {
        r.days.add(
          AttendanceDay(date: DateTime(2026, 10, day), streak: 1, points: 1),
        );
      }
      r.last = r.today;
      r.streak = 1;
      r.balance = 4;
      await card(t, await controller(r));
      expect(find.textContaining('이번 주 4일 출석'), findsOneWidget);
      expect(find.bySemanticsLabel('10월 21일, 출석 전'), findsOneWidget);
      expect(find.bySemanticsLabel('10월 23일, 출석 완료'), findsOneWidget);
      expect(find.text('오늘 출석 완료!  +100P 받았어요'), findsOneWidget);
      expect(find.textContaining('+10P'), findsNothing);
      await finish(t);
    },
  );
  testWidgets('direct home stamp locks rapid taps and refreshes reward', (
    t,
  ) async {
    final r = WeekRepository()..gate = Completer<void>();
    var synced = 0;
    await card(
      t,
      await controller(r),
      onStamped: () async {
        synced++;
      },
    );
    final action = find.byKey(const ValueKey('home-attendance-action'));
    await t.tap(action);
    await t.pump();
    await t.tap(action, warnIfMissed: false);
    await t.pump();
    expect(r.checkInCalls, 1);
    r.gate!.complete();
    await t.pumpAndSettle();
    expect(r.paidCount, 1);
    expect(synced, 1);
    expect(find.text('오늘 출석 완료!  +100P 받았어요'), findsOneWidget);
    expect(find.textContaining('이번 주 1일 출석'), findsOneWidget);
    await finish(t);
  });
  testWidgets(
    'home stamp recovers an ambiguous server response without a second payment',
    (t) async {
      final r = WeekRepository()..failure = FakeCheckInFailure.beforeServer;
      await card(t, await controller(r));
      await tap(t, find.byKey(const ValueKey('home-attendance-action')));
      expect(find.text('출석을 처리하지 못했어요. 다시 시도해주세요.'), findsOneWidget);
      expect(r.paidCount, 0);
      r.failure = FakeCheckInFailure.afterServer;
      await tap(t, find.byKey(const ValueKey('home-attendance-action')));
      expect(r.paidCount, 1);
      expect(find.text('오늘 출석 완료!  +100P 받았어요'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'failed weekly history is retryable and never invents past stamps',
    (t) async {
      final r = WeekRepository()..failWeek = true;
      r.attendedBefore(3);
      await r.checkIn();
      await card(t, await controller(r));
      expect(find.text('주간 기록 다시 불러오기'), findsOneWidget);
      expect(find.bySemanticsLabel('10월 23일, 기록 확인 중'), findsOneWidget);
      r.failWeek = false;
      await tap(t, find.text('주간 기록 다시 불러오기'));
      expect(find.bySemanticsLabel('10월 23일, 출석 완료'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets('new server day updates date, weekly strip and stamp action', (
    t,
  ) async {
    final r = WeekRepository(today: DateTime(2026, 10, 25));
    await r.checkIn();
    final c = await controller(r);
    await card(t, c);
    r.today = DateTime(2026, 10, 26);
    await c.refresh();
    await t.pumpAndSettle();
    expect(find.text('출석체크하고 500P 받기'), findsOneWidget);
    expect(find.bySemanticsLabel('오늘, 10월 26일, 출석 전'), findsOneWidget);
    expect(find.textContaining('이번 주 0일 출석'), findsOneWidget);
    await finish(t);
  });
  testWidgets('all home cards fit narrow phones with enlarged text', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final r = WeekRepository()..attendedBefore(2);
    await r.checkIn();
    r.balance = 123456789;
    final c = await controller(r);
    final pet = PetPreviewController()..ready = true;
    pet.adopt('콩이');
    addTearDown(pet.dispose);
    await mount(
      t,
      AttendanceScope(
        controller: c,
        child: HomeTab(
          petPreview: pet,
          onOpenPet: () {},
          activityRepository: FakeActivityRepository(),
        ),
      ),
      scale: 2,
    );
    expect(t.takeException(), isNull);
    await tap(t, find.text('즐겨찾는 시설'));
    expect(find.text('아직 즐겨찾는 시설이 없어요.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await finish(t);
  });
  testWidgets(
    'home attendance updates pet experience and shared wallet exactly once',
    (t) async {
      final r = WeekRepository();
      final pet = PetPreviewController(repository: PetAttendanceRepository(r));
      addTearDown(pet.dispose);
      await mount(
        t,
        MainShell(
          attendanceRepository: r,
          petController: pet,
          activityRepository: FakeActivityRepository(),
          facilityPage: const SizedBox(),
        ),
      );
      await tap(t, find.text('닫기'));
      await tap(t, find.byKey(const ValueKey('home-attendance-action')));
      expect(r.paidCount, 1);
      expect(r.balance, 1);
      expect(pet.points, 1);
      expect(pet.experience, 10);
      await tap(t, find.byKey(const ValueKey('home-points')));
      expect(find.byType(AttendanceDialog), findsOneWidget);
      await tap(t, find.text('닫기'));
      expect(r.paidCount, 1);
      expect(pet.experience, 10);
      await finish(t);
    },
  );
  testWidgets(
    'after all streak milestones home does not promise another seven day bonus',
    (t) async {
      final r = WeekRepository()..attendedBefore(30);
      await r.checkIn();
      await card(t, await controller(r));
      expect(find.textContaining('꾸준히 함께해요'), findsOneWidget);
      expect(find.textContaining('7일 연속 보너스'), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'stamp overlapping a background pet load queues one growth sync',
    (t) async {
      final r = WeekRepository();
      final repo = PetAttendanceRepository(r)..loadGate = Completer<void>();
      final pet = PetPreviewController(repository: repo);
      addTearDown(pet.dispose);
      await mount(
        t,
        MainShell(
          attendanceRepository: r,
          petController: pet,
          activityRepository: FakeActivityRepository(),
          facilityPage: const SizedBox(),
        ),
      );
      await tap(t, find.text('닫기'));
      await tap(t, find.byKey(const ValueKey('home-attendance-action')));
      expect(r.paidCount, 1);
      expect(pet.busy, true);
      repo.loadGate!.complete();
      await t.pumpAndSettle();
      expect(pet.experience, 10);
      expect(pet.points, 1);
      expect(r.paidCount, 1);
      await finish(t);
    },
  );
}

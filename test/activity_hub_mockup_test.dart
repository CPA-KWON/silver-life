import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/activity/activity_hub_page.dart';
import 'package:silver_life/activity/activity_hub_widgets.dart';
import 'package:silver_life/attendance/attendance_controller.dart';
import 'package:silver_life/attendance/attendance_dialog.dart';
import 'package:silver_life/home/main_shell.dart';
import 'package:silver_life/pet/pet_home_pages.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/pet/pet_today_page.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';
import 'support/fake_attendance_repository.dart';
import 'support/widget_actions.dart';

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  PetPreviewController pet() {
    final p = PetPreviewController()..adopt('콩이');
    p.missions.addAll([
      {
        'stage': 1,
        'progress': 3,
        'target': 3,
        'completed': true,
        'claimed': true,
      },
      {
        'stage': 2,
        'progress': 0,
        'target': 1,
        'completed': false,
        'claimed': false,
      },
      {
        'stage': 3,
        'progress': 0,
        'target': 1,
        'completed': false,
        'claimed': false,
      },
    ]);
    addTearDown(p.dispose);
    return p;
  }

  FakeActivityRepository repo() {
    final r = FakeActivityRepository();
    r.programs.addAll([
      {
        ...r.programs.first,
        'id': 'hobby',
        'title': '동네 도예 교실',
        'category': '문화·취미',
      },
      {
        ...r.programs.first,
        'id': 'learning',
        'title': '스마트폰 배우기',
        'category': '배움·디지털',
      },
    ]);
    return r;
  }

  testWidgets('keyword search opens and filters real repository program data', (
    t,
  ) async {
    await mount(t, ActivityHubPage(repository: repo(), petController: pet()));
    await t.enterText(
      find.byKey(const ValueKey('activity-hub-search')),
      '  도예  ',
    );
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(find.text('전체 프로그램'), findsOneWidget);
    expect(find.text('동네 도예 교실'), findsOneWidget);
    expect(find.text('가벼운 산책'), findsNothing);
    expect(find.text('스마트폰 배우기'), findsNothing);
    await t.enterText(find.widgetWithText(TextField, '프로그램 검색'), '없는 활동');
    await t.pumpAndSettle();
    expect(find.text('현재 모집 중인 프로그램이 없어요.'), findsOneWidget);
    await finish(t);
  });
  testWidgets(
    'four quick categories filter using the existing category taxonomy',
    (t) async {
      for (final label in activityQuickCategories.keys) {
        final p = pet();
        await mount(t, ActivityHubPage(repository: repo(), petController: p));
        await tap(t, find.widgetWithText(OutlinedButton, label));
        final expected = label == '취미'
            ? '동네 도예 교실'
            : label == '교육'
            ? '스마트폰 배우기'
            : '가벼운 산책';
        expect(find.text(expected), findsOneWidget);
        final others = ['가벼운 산책', '동네 도예 교실', '스마트폰 배우기']..remove(expected);
        for (final title in others) {
          expect(find.text(title), findsNothing);
        }
        await finish(t);
      }
    },
  );
  testWidgets(
    'weekly summary follows shared pet state and keeps old missions reachable',
    (t) async {
      final p = pet();
      await mount(t, ActivityHubPage(repository: repo(), petController: p));
      expect(find.text('1 / 3단계'), findsOneWidget);
      await tap(t, find.text('주간 미션'));
      final page = t.widget<PetTodayPage>(find.byType(PetTodayPage));
      expect(page.pet, same(p));
      expect(page.missionsOnly, true);
      expect(find.text('광고 보상'), findsNothing);
      expect(find.text('동네 프로그램'), findsNothing);
      await tap(t, find.text('프로그램별 주간 미션 보기'));
      expect(find.text('프로그램별 주간 미션'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'unknown mission data is not shown as fabricated progress and can retry',
    (t) async {
      final p = PetPreviewController()..error = 'offline';
      addTearDown(p.dispose);
      await mount(t, ActivityHubPage(repository: repo(), petController: p));
      expect(find.text('다시 확인'), findsOneWidget);
      expect(find.text('0 / 3단계'), findsNothing);
      await tap(t, find.text('주간 미션'));
      expect(find.text('미션 정보를 불러오지 못했어요'), findsOneWidget);
      expect(find.text('다시 확인하기'), findsOneWidget);
      expect(find.text('프로그램별 주간 미션 보기'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'wallet uses existing attendance controller and calendar, not mockup amount',
    (t) async {
      final attendance = AttendanceController(
        repository: FakeAttendanceRepository(),
      );
      addTearDown(attendance.dispose);
      await attendance.refresh();
      await mount(
        t,
        AttendanceScope(
          controller: attendance,
          child: ActivityHubPage(repository: repo(), petController: pet()),
        ),
      );
      final pill = t.widget<ActivityWalletPill>(
        find.byType(ActivityWalletPill),
      );
      expect(pill.balance, attendance.status!.balance);
      await tap(t, find.byType(ActivityWalletPill));
      expect(find.byType(AttendanceDialog), findsOneWidget);
      await tap(t, find.text('닫기'));
      await finish(t);
    },
  );
  testWidgets(
    'pet banner reuses home pet route while retaining the map instance',
    (t) async {
      await mount(
        t,
        MainShell(
          petController: pet(),
          activityRepository: repo(),
          facilityPage: const ColoredBox(
            key: ValueKey('map-kept'),
            color: Colors.blue,
          ),
        ),
      );
      await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
      final map = t.element(find.byKey(const ValueKey('map-kept')));
      await tap(t, find.widgetWithText(NavigationDestination, '홈'));
      await tap(t, find.text('콩이 만나러 가기 →'));
      await tap(t, find.widgetWithText(NavigationDestination, '활동'));
      await tap(t, find.text('활동하면 콩이도 자라요'));
      expect(find.byType(PetHomePage), findsOneWidget);
      expect(
        t.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
      expect(t.element(find.byKey(const ValueKey('map-kept'))), same(map));
      await finish(t);
    },
  );
  testWidgets('narrow 200 percent layout keeps all purposes accessible', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await mount(
      t,
      ActivityHubPage(repository: repo(), petController: pet()),
      scale: 2,
    );
    await tap(t, find.text('경험 나눔'));
    expect(find.text('내 경험 관리'), findsOneWidget);
    expect(t.takeException(), isNull);
    await finish(t);
  });
}

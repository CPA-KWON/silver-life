import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/home/home_tab.dart';
import 'package:silver_life/home/main_shell.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'home activity entry replaces the dashboard with a dedicated destination',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final repo = FakeActivityRepository();
      repo.missions.addAll([
        {'status': 'completed'},
        {'status': 'approved'},
      ]);
      await mount(t, HomeTab(activityRepository: repo), scale: 2);
      expect(find.text('더 둘러보기'), findsOneWidget);
      expect(find.text('맞춤 활동 찾기'), findsOneWidget);
      expect(find.text('이번 주 활동 현황'), findsNothing);
      expect(find.text('시작 전'), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );

  testWidgets('empty home stays usable with large text on a small phone', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final repo = FakeActivityRepository();
    await mount(t, MainShell(activityRepository: repo), scale: 2);
    expect(find.text('이번 주 활동 현황'), findsNothing);
    expect(find.text('시작 전'), findsNothing);
    expect(find.text('동네 모임 둘러보기'), findsOneWidget);
    expect(t.takeException(), isNull);
    await tap(t, find.widgetWithText(NavigationDestination, '활동'));
    await tap(t, find.text('경험 나눔'));
    expect(find.text('내 경험 관리'), findsOneWidget);
    expect(t.takeException(), isNull);
    await tap(t, find.widgetWithText(NavigationDestination, '홈'));
    await tap(t, find.text('내 정보'));
    await tap(t, find.text('즐겨찾는 시설'));
    expect(find.text('아직 즐겨찾는 시설이 없어요.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await finish(t);
  });
}

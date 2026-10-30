import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/home/main_shell.dart';
import 'package:silver_life/auth/auth_gate.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/pet/pet_preview_pages.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

Widget still(Widget page) => Builder(
  builder: (c) => MediaQuery(
    data: MediaQuery.of(c).copyWith(disableAnimations: true),
    child: page,
  ),
);
void main() {
  test('preview economy uses actual catalogue, explicit growth and one-time claims', () async {
    final p = PetPreviewController()..adopt('콩이');
    addTearDown(p.dispose);
    await p.run('attendance');
    await p.run('attendance');
    await p.run('walk_start');
    await p.run('walk_sync', {'steps': 2014});
    await p.run('walk_reward');
    await p.run('walk_reward');
    expect(p.points, 1281);
    expect(p.experience, 20);
    await p.run('buy', {'item': 'knit'});
    await p.run('buy', {'item': 'knit'});
    expect(p.points, 1031);
    await p.run('wear', {
      'items': ['knit'],
    });
    expect(p.worn, {'knit'});
    expect(p.stage, 0);
    await p.run('feed', {'item': 'sweet'});
    expect(p.snacks['sweet'], 1);
    expect(p.experience, 25);
    for (var i = 0; i < 3; i++) {
      await p.run('feed', {'item': 'food'});
    }
    await expectLater(p.run('feed', {'item': 'food'}), throwsStateError);
    await p.run('preview_ready');
    expect(p.stage, 0);
    expect(p.canGrow, true);
    await p.run('grow');
    expect(p.stage, 1);
  });
  test(
    'failed purchase and unavailable outfit leave wallet intact; ads capped',
    () async {
      final p = PetPreviewController(initialPoints: 50)..adopt('콩이');
      addTearDown(p.dispose);
      await expectLater(p.run('buy', {'item': 'knit'}), throwsStateError);
      expect(p.points, 50);
      expect(p.owned, isEmpty);
      await expectLater(p.run('buy', {'item': 'rain'}), throwsStateError);
      await p.run('ad_claim');
      await p.run('ad_claim');
      await expectLater(p.run('ad_claim'), throwsStateError);
      expect(p.points, 90);
    },
  );
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('five tabs retain map and pet screen state', (t) async {
    final pet = PetPreviewController()..adopt('콩이');
    addTearDown(pet.dispose);
    await mount(
      t,
      still(
        MainShell(
          petController: pet,
          activityRepository: FakeActivityRepository(),
          facilityPage: const ColoredBox(
            key: ValueKey('map'),
            color: Colors.blue,
          ),
        ),
      ),
    );
    await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
    final map = t.element(find.byKey(const ValueKey('map')));
    await tap(t, find.widgetWithText(NavigationDestination, '홈'));
    await tap(t, find.text('콩이 만나러 가기 →'));
    expect(find.text('먹이 주기'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
    expect(identical(map, t.element(find.byKey(const ValueKey('map')))), true);
    await tap(t, find.widgetWithText(NavigationDestination, '홈'));
    expect(find.text('먹이 주기'), findsOneWidget);
    await finish(t);
  });
  testWidgets('new mockup screens remain usable at 200 percent text', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final pet = PetPreviewController()..adopt('콩이');
    addTearDown(pet.dispose);
    for (final page in [
      PetHomePage(pet: pet),
      PetWardrobePage(pet: pet),
      PetWalkPage(pet: pet),
      PetTodayPage(pet: pet),
      PetGrowthPage(pet: pet),
      PetRecordsPage(pet: pet),
    ]) {
      await mount(t, still(page), scale: 2);
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '${page.runtimeType}');
      await finish(t);
    }
  });
  testWidgets(
    'feeding moves through owned snack to result without spending points',
    (t) async {
      final pet = PetPreviewController()..adopt('콩이');
      addTearDown(pet.dispose);
      await mount(t, still(PetHomePage(pet: pet)));
      await tap(t, find.text('먹이 주기'));
      await tap(t, find.text('고구마 간식'));
      await tap(t, find.text('고구마 간식 주기'));
      await t.pumpAndSettle();
      expect(pet.points, 1250);
      expect(pet.snacks['sweet'], 1);
      expect(pet.experience, 5);
      expect(find.text('고구마 간식을 줬어요'), findsOneWidget);
      await tap(t, find.text('확인'));
      await finish(t);
    },
  );
  testWidgets('sign-out removes fullscreen pet routes as well as tab routes', (
    t,
  ) async {
    final pet = PetPreviewController()..adopt('콩이');
    addTearDown(pet.dispose);
    await mount(
      t,
      still(
        AuthGate(
          signedInPage: MainShell(
            petController: pet,
            activityRepository: FakeActivityRepository(),
            facilityPage: const SizedBox(),
          ),
        ),
      ),
    );
    await tap(t, find.text('콩이 만나러 가기 →'));
    await tap(t, find.text('옷 입히기'));
    expect(find.text('되돌리기'), findsNothing);
    expect(find.text('옷 입히기'), findsOneWidget);
    await Supabase.instance.client.auth.signOut();
    await t.pumpAndSettle();
    expect(find.text('옷 입히기'), findsNothing);
    expect(find.text('로그인'), findsWidgets);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('옷 입히기'), findsNothing);
    await finish(t);
  });
}

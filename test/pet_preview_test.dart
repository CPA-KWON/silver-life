import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/home/main_shell.dart';
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
  group('session-only preview economy', () {
    test(
      'activity rewards cannot be claimed twice; clothes do not grow the pet',
      () {
        final pet = PetPreviewController()..adopt('콩이');
        addTearDown(pet.dispose);
        pet.attendance();
        pet.attendance();
        pet.walk();
        pet.walk();
        pet.completeProgram();
        pet.completeProgram();
        expect(pet.points, 28);
        expect(pet.experience, 45);
        pet.purchase('hat');
        pet.purchase('hat');
        pet.wear('hat');
        expect(pet.points, 18);
        expect(pet.experience, 45);
        expect(pet.worn, {'hat'});
        pet.wear('hat', remove: true);
        expect(pet.worn, isEmpty);
        expect(pet.owned, {'hat'});
      },
    );
    test(
      'failed purchases leave wallet and inventory intact; ads are capped',
      () {
        final pet = PetPreviewController()..adopt('콩이');
        addTearDown(pet.dispose);
        pet.purchase('knit');
        expect(() => pet.purchase('hat'), throwsStateError);
        expect(pet.points, 0);
        expect(pet.owned, {'knit'});
        pet.advert();
        pet.advert();
        expect(() => pet.advert(), throwsStateError);
        expect(pet.points, 2);
        expect(pet.experience, 0);
      },
    );
    test('free care is once and extra snacks do not duplicate growth', () {
      final pet = PetPreviewController()..adopt('콩이');
      addTearDown(pet.dispose);
      pet.feed();
      pet.feed(special: true);
      expect(() => pet.feed(), throwsStateError);
      expect(pet.experience, 5);
      expect(pet.points, 17);
      expect(pet.fullness, 5);
      pet.previewStage(1);
      expect(pet.stageName, '성장기');
      pet.previewStage(2);
      expect(pet.stageName, '성체');
      pet.reset();
      expect(pet.adopted, false);
      expect(pet.points, 20);
      expect(pet.records, isEmpty);
      expect(pet.owned, isEmpty);
    });
  });

  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'adoption, care and outfit survive tabs; map element stays mounted',
    (t) async {
      await mount(
        t,
        still(
          MainShell(
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
      await tap(t, find.text('콩이 만나러 가기'));
      await t.enterText(find.byType(TextFormField), '보리');
      await t.scrollUntilVisible(
        find.text('함께 시작하기'),
        180,
        scrollable: find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tap(t, find.text('함께 시작하기'));
      expect(find.text('보리의 집'), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tap(t, find.text('먹이 주기'));
      await tap(t, find.text('기본 사료 · 무료'));
      expect(find.text('맛있게 먹었어요'), findsOneWidget);
      await tap(t, find.text('확인'));
      await tap(t, find.text('옷 입히기'));
      await tap(t, find.text('구매하고 입히기'));
      await tap(
        t,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('구매하고 입히기'),
        ),
      );
      await tap(t, find.text('확인'));
      expect(find.text('착용 중'), findsOneWidget);
      await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
      expect(
        identical(map, t.element(find.byKey(const ValueKey('map')))),
        true,
      );
      await tap(t, find.widgetWithText(NavigationDestination, '홈'));
      expect(find.text('착용 중'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('보리의 집'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('반려동물 만나기'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );

  testWidgets('preview screens fit narrow phones at 200 percent text', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 900));
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
      await t.drag(find.byType(ListView).first, const Offset(0, -1600));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: '${page.runtimeType}');
      await finish(t);
    }
  });

  testWidgets(
    'walk preview gives a single reward without location permission',
    (t) async {
      final pet = PetPreviewController()..adopt('콩이');
      addTearDown(pet.dispose);
      await mount(t, still(PetWalkPage(pet: pet)));
      await tap(t, find.text('산책 화면 시작하기'));
      await tap(t, find.text('진행 상황 미리보기'));
      await tap(t, find.text('진행 상황 미리보기'));
      await tap(t, find.text('완료 · 임시 보상 받기'));
      expect(pet.points, 22);
      expect(pet.experience, 10);
      expect(find.text('반려동물에게 돌아가기'), findsOneWidget);
      await finish(t);
    },
  );
}

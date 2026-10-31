import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silver_life/attendance/attendance_ads.dart';
import 'package:silver_life/attendance/attendance_controller.dart';
import 'package:silver_life/attendance/attendance_dialog.dart';
import 'package:silver_life/core/release_flags.dart';
import 'package:silver_life/pet/pet_ads_service.dart';
import 'package:silver_life/pet/pet_onboarding.dart';
import 'package:silver_life/profile/account_settings_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/pet/pet_today_page.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/pet/pet_shop_page.dart';

import 'support/fake_attendance_repository.dart';
import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

/// 출시 빌드에서 숨겨야 하는 것들. 테스트는 테스트용 빌드로 돌기 때문에
/// debugTreatAsReleaseBuild로 출시 빌드처럼 만들어 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugTreatAsReleaseBuild = null);
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> openShop(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 6000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final pet = PetPreviewController(initialPoints: 200);
    await pet.run('adopt', {'name': '나비', 'species': 'cat'});
    addTearDown(pet.dispose);
    await mount(t, PetShopPage(pet: pet));
  }

  testWidgets('release build hides paid items and purchase buttons', (t) async {
    debugTreatAsReleaseBuild = true;
    expect(paidItemsVisible, isFalse);
    await openShop(t);
    expect(find.text('꽃 가디건'), findsNothing);
    expect(find.text('특별 구매'), findsNothing);
    expect(find.text('구매한 아이템 다시 확인'), findsNothing);
    expect(find.textContaining('Google Play'), findsNothing);
    expect(find.text('결제 미리보기'), findsNothing);
    // 포인트로 사는 아이템은 그대로 있다.
    expect(find.text('P 아이템'), findsOneWidget);
    await finish(t);
  });

  testWidgets('test build still shows paid items', (t) async {
    expect(paidItemsVisible, isTrue);
    await openShop(t);
    expect(find.text('꽃 가디건'), findsOneWidget);
    expect(find.text('특별 구매'), findsOneWidget);
    expect(find.text('구매한 아이템 다시 확인'), findsOneWidget);
    await finish(t);
  });

  Future<void> openAttendance(WidgetTester t, {required bool attended}) async {
    t.view.physicalSize = const Size(900, 2000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = FakeAttendanceRepository();
    if (attended) await repo.checkIn();
    final controller = AttendanceController(repository: repo);
    await controller.refresh();
    addTearDown(controller.dispose);
    await t.pumpWidget(
      MaterialApp(
        home: AttendanceDialog(controller: controller, ads: AttendanceAds()),
      ),
    );
    await t.pumpAndSettle();
  }

  group('rewarded ads', () {
    test('a release build needs a production ad unit', () {
      expect(rewardedAdVisible(''), isTrue);
      debugTreatAsReleaseBuild = true;
      expect(rewardedAdVisible(''), isFalse);
      expect(rewardedAdVisible('ca-app-pub-1/2'), isTrue);
      expect(PetAdsService.visible, isFalse);
      expect(AttendanceAds().visible, isFalse);
    });

    testWidgets('attendance dialog has no ad card without an ad unit', (
      t,
    ) async {
      debugTreatAsReleaseBuild = true;
      await openAttendance(t, attended: true);
      expect(find.byKey(const ValueKey('attendance-ad-card')), findsNothing);
      expect(find.textContaining('광고'), findsNothing);
      await finish(t);
      await openAttendance(t, attended: false);
      expect(find.textContaining('광고'), findsNothing);
      await finish(t);
    });

    testWidgets('attendance dialog keeps the ad card in a test build', (
      t,
    ) async {
      await openAttendance(t, attended: true);
      expect(find.byKey(const ValueKey('attendance-ad-card')), findsOneWidget);
      await finish(t);
    });

    Future<void> openToday(WidgetTester t) async {
      t.view.physicalSize = const Size(900, 6000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final pet = PetPreviewController(initialPoints: 200);
      await pet.run('adopt', {'name': '나비', 'species': 'cat'});
      addTearDown(pet.dispose);
      await mount(t, PetTodayPage(pet: pet));
    }

    testWidgets('pet ad reward is hidden without an ad unit', (t) async {
      debugTreatAsReleaseBuild = true;
      await openToday(t);
      expect(find.text('짧은 광고 보기'), findsNothing);
      expect(find.text('광고 보상'), findsNothing);
      await finish(t);
    });

    testWidgets('pet ad reward stays in a test build', (t) async {
      await openToday(t);
      expect(find.text('짧은 광고 보기'), findsOneWidget);
      await finish(t);
    });
  });

  group('not-ready features', () {
    Future<void> openAccount(WidgetTester t) async {
      t.view.physicalSize = const Size(900, 4000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      backend.reset();
      await backend.signIn();
      await mount(t, const AccountSettingsPage());
    }

    testWidgets('release build hides phone verification until it is on', (
      t,
    ) async {
      debugTreatAsReleaseBuild = true;
      await openAccount(t);
      expect(find.text('휴대폰 번호'), findsNothing);
      expect(find.textContaining('준비'), findsNothing);
      // 나머지 회원정보는 그대로 쓸 수 있다.
      expect(find.text('회원 탈퇴'), findsOneWidget);
      await finish(t);
    });

    testWidgets('test build keeps phone verification', (t) async {
      await openAccount(t);
      expect(find.text('휴대폰 번호'), findsWidgets);
      await finish(t);
    });

    testWidgets('release build has no design preview or setup wording', (
      t,
    ) async {
      debugTreatAsReleaseBuild = true;
      final pet = PetPreviewController();
      addTearDown(pet.dispose);
      await mount(t, PetConnectionPage(pet: pet));
      expect(find.text('디자인 미리보기 열기'), findsNothing);
      expect(find.textContaining('준비'), findsNothing);
      expect(find.textContaining('서버 설정'), findsNothing);
      expect(find.text('다시 연결하기'), findsOneWidget);
      await finish(t);
    });

    testWidgets('test build keeps the design preview', (t) async {
      final pet = PetPreviewController();
      addTearDown(pet.dispose);
      await mount(t, PetConnectionPage(pet: pet));
      expect(find.text('디자인 미리보기 열기'), findsOneWidget);
      await finish(t);
    });
  });
}

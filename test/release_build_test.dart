import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silver_life/core/release_flags.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/pet/pet_shop_page.dart';

import 'support/widget_actions.dart';

/// 출시 빌드에서 숨겨야 하는 것들. 테스트는 테스트용 빌드로 돌기 때문에
/// debugTreatAsReleaseBuild로 출시 빌드처럼 만들어 확인한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugTreatAsReleaseBuild = null);

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
}

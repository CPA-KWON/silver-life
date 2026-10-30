import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/pet/pet_catalog.dart';
import 'package:silver_life/pet/pet_walk_settings.dart';
import 'package:silver_life/pet/pet_shop_page.dart';
import 'package:silver_life/pet/pet_safe_walk_page.dart';

import 'support/widget_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cat selection keeps wallet, uses cat snacks and enforces item ownership/slots', () async {
    final pet = PetPreviewController(initialPoints: 500);
    await pet.run('adopt', {'name': '나비', 'species': 'cat'});
    expect(pet.species, 'cat');
    expect(pet.points, 500);
    expect(pet.foods[1].name, '촉촉 참치');
    await pet.run('buy', {'item': 'cat_stripe_knit'});
    expect(pet.points, 350);
    await expectLater(
      pet.run('buy', {'item': 'dog_walk_vest'}),
      throwsStateError,
    );
    expect(pet.points, 350);
    await pet.run('buy', {'item': 'cat_walk_vest'});
    await expectLater(
      pet.run('wear', {
        'items': ['cat_stripe_knit', 'cat_walk_vest'],
      }),
      throwsStateError,
    );
    expect(pet.worn, isEmpty);
    await pet.run('wear', {
      'items': ['cat_stripe_knit'],
    });
    expect(pet.worn, {'cat_stripe_knit'});
    await expectLater(
      pet.run('buy', {'item': 'cat_flower_cardigan'}),
      throwsStateError,
    );
    pet.dispose();
  });
  test(
    'contact settings are scoped by owner and paused time is excluded',
    () async {
      SharedPreferences.setMockInitialValues({});
      final one = PetWalkSettings('one')
        ..name = '가족'
        ..phone = '010-1234-5678';
      await one.save();
      final two = PetWalkSettings('two');
      await two.load();
      expect(two.phone, isEmpty);
      final again = PetWalkSettings('one');
      await again.load();
      expect(again.phone, '010-1234-5678');
      expect(PetWalkSettings.validPhone('010-1234-5678'), true);
      expect(PetWalkSettings.validPhone('010-12'), false);
      final now = DateTime(2026, 10, 29, 10);
      again.pausedSeconds = 60;
      again.pausedAt = now.subtract(const Duration(seconds: 30));
      expect(
        again.activeSeconds(now.subtract(const Duration(seconds: 180)), now),
        90,
      );
    },
  );
  testWidgets(
    'test purchase cancellation preserves inventory; explicit success grants only preview item',
    (t) async {
      final pet = PetPreviewController(initialPoints: 200);
      await pet.run('adopt', {'name': '나비', 'species': 'cat'});
      addTearDown(pet.dispose);
      await mount(t, PetShopPage(pet: pet));
      await tap(t, find.text('꽃 가디건'));
      await tap(t, find.text('테스트 결제 화면 보기'));
      await tap(t, find.text('구매 취소'));
      await tap(t, find.text('확인'));
      expect(pet.owned.contains('cat_flower_cardigan'), isFalse);
      expect(pet.points, 200);
      await tap(t, find.text('꽃 가디건'));
      await tap(t, find.text('테스트 결제 화면 보기'));
      await tap(t, find.text('테스트 구매 성공'));
      await tap(t, find.text('확인'));
      expect(pet.owned.contains('cat_flower_cardigan'), isTrue);
      expect(pet.points, 200);
      expect(pet.isPreview, isTrue);
      await finish(t);
    },
  );

  testWidgets(
    'walk contact registration validates a number and survives reopening',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      final pet = PetPreviewController()..adopt('콩이');
      addTearDown(pet.dispose);
      await mount(t, PetWalkPage(pet: pet));
      await tap(t, find.text('연락처를 등록해요'));
      await t.enterText(find.byType(TextFormField).first, '가족');
      await visible(t, find.byType(TextFormField).last);
      await t.enterText(find.byType(TextFormField).last, '123');
      await tap(t, find.text('번호 확인하기'));
      expect(find.text('전화번호를 확인해주세요.'), findsOneWidget);
      await visible(t, find.byType(TextFormField).last);
      await t.enterText(find.byType(TextFormField).last, '010-1234-5678');
      await tap(t, find.text('번호 확인하기'));
      await tap(t, find.text('맞아요, 저장할게요'));
      final saved = PetWalkSettings('preview');
      await saved.load();
      expect(saved.name, '가족');
      expect(saved.phone, '010-1234-5678');
      await tap(t, find.text('가족 · 010-1234-5678'));
      expect(find.text('등록한 연락처 지우기'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );

  test('20 items have original thumbnails and all growth fittings; models contain matching wearable meshes', () async {
    expect(PetItem.all.length, 20);
    expect(PetItem.all.map((i) => i.id).toSet().length, 20);
    for (final kind in ['dog', 'cat']) {
      expect(
        PetItem.all.where((i) => i.species == kind && i.slot == 'body').length,
        5,
      );
      expect(
        PetItem.all.where((i) => i.species == kind && i.slot != 'body').length,
        5,
      );
      for (final stage in ['baby', 'junior', 'adult']) {
        final data = await rootBundle.load(
          'assets/pet/models/${kind}_$stage.glb',
        );
        expect(data.getUint32(0, Endian.little), 0x46546c67);
        final size = data.getUint32(12, Endian.little);
        final gltf = jsonDecode(
          utf8.decode(data.buffer.asUint8List(data.offsetInBytes + 20, size)),
        );
        final materials = (gltf['materials'] as List)
            .map((m) => m['name'])
            .toSet();
        for (final i in PetItem.all.where((i) => i.species == kind)) {
          expect(materials.contains('item:${i.id}'), true);
        }
        expect(
          (gltf['animations'] as List)
              .map((a) => a['name'])
              .toSet()
              .containsAll(['Idle', 'Walk', 'Eat', 'Happy', 'Jump']),
          true,
        );
      }
    }
    for (final item in PetItem.all) {
      expect(
        (await rootBundle.load(item.thumbnail)).lengthInBytes,
        greaterThan(0),
      );
      for (var s = 0; s < 3; s++) {
        expect(
          (await rootBundle.load(item.fitting(s))).lengthInBytes,
          greaterThan(0),
        );
      }
    }
  });
}

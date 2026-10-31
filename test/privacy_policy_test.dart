import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/profile/privacy_policy_page.dart';

import 'support/widget_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> policyTexts(WidgetTester t) async {
    t.view.physicalSize = const Size(900, 8000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await mount(t, const PrivacyPolicyPage());
    return [
      for (final e in find.byType(Text).evaluate())
        (e.widget as Text).data ?? '',
    ];
  }

  testWidgets('policy covers what the app actually handles', (t) async {
    final text = (await policyTexts(t)).join('\n');
    for (final word in [
      '사진',
      '걸음',
      '친구',
      '체크인',
      '광고 ID',
      'AdMob',
      '주문 번호',
      '재직 확인 자료',
      '위치',
      'Supabase',
      '네이버',
      'Google',
    ]) {
      expect(text, contains(word));
    }
    expect(text, isNot(contains('등 다른 목적으로 이용하지 않습니다')));
    await finish(t);
  });

  testWidgets('published web page matches the app text', (t) async {
    final page = File('docs/privacy-policy.html').readAsStringSync();
    String escape(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
    final texts = await policyTexts(t);
    var checked = 0;
    for (final block in texts.where((s) => s.length > 20)) {
      for (final line in block.split('\n')) {
        expect(page, contains(escape(line)));
        checked++;
      }
    }
    expect(checked, greaterThan(20));
    await finish(t);
  });
}

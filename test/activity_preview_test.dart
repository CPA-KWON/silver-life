import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/activity/activity_hub_page.dart';

import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

void main() {
  testWidgets('render v5 activity screens with Korean font and sample data', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.runAsync(() async {
      final font = FontLoader('Pretendard')
        ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'));
      await font.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    });
    final r = FakeActivityRepository()
      ..pref = {'place_name': '우리 동네'}
      ..addSupport();
    r.programs.add({
      ...r.programs.first,
      'id': 'class',
      'title': '복지관 무료 수업',
      'place_name': '이웃 복지관',
      'fee': 0,
      'sponsored': false,
    });
    r.programs.add({
      ...r.programs.first,
      'id': 'group',
      'title': '이웃과 함께하는 원예 모임',
      'place_name': '마을 정원',
      'fee': 0,
      'sponsored': false,
    });
    for (var i = 0; i < 3; i++) {
      final p = r.programs[[0, 2, 3][i]];
      r.missions.add({
        'stage': i + 1,
        'program_id': p['id'],
        'program': p,
        'status': i == 0
            ? 'completed'
            : i == 1
            ? 'approved'
            : 'unstarted',
      });
    }
    r.offers.add({
      'id': 'offer',
      'title': '30년 재봉 경험을 나눠요',
      'category': '생활·기술',
      'active': true,
    });
    for (final e in {'activity_missions': 0, 'experience_bank': 1}.entries) {
      final key = GlobalKey();
      await mount(
        t,
        RepaintBoundary(
          key: key,
          child: ActivityHubPage(repository: r, initialTab: e.value),
        ),
      );
      expect(t.takeException(), isNull);
      final destination = Platform.environment['ACTIVITY_PREVIEW_DIR'];
      if (destination != null) {
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final im = await boundary.toImage(pixelRatio: 2);
          final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          await Directory(destination).create(recursive: true);
          await File('$destination/${e.key}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          im.dispose();
        });
      }
    }
    await finish(t);
  });
}

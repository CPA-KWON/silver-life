import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/activity/activity_hub_page.dart';
import 'package:silver_life/activity/activity_hub_widgets.dart';
import 'package:silver_life/activity/activity_welfare_catalog.dart';
import 'package:silver_life/activity/activity_welfare_detail.dart';
import 'package:silver_life/activity/activity_program_card.dart';
import 'package:silver_life/pet/pet_design.dart';

import 'support/fake_activity_repository.dart';
import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

final raw = <String, dynamic>{
  'id': 7,
  'facility_name': '상도은빛복지관',
  'title': '은빛 요가',
  'category': '운동/댄스',
  'schedule': '매주 월요일 10:00~11:00',
  'target': '동작구 지역 어르신',
  'fee': '무료 · 재료비 별도',
  'how_to_apply': '기관 방문 접수',
};
final centers = <Map<String, dynamic>>[
  {
    'name': '상도은빛어르신복지관',
    'lat': 37.5064542,
    'lng': 126.9513983,
    'address': '서울특별시 동작구 매봉로 36',
    'telephone': '02-000-0000',
  },
];
void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  test('institution categories map to all four existing quick themes', () {
    for (final label in activityQuickCategories.keys) {
      final p = {
        ...raw,
        'category': label == '취미'
            ? '음악/미술'
            : label == '교육'
            ? '정보화'
            : '운동/댄스',
      };
      expect(welfareActivityCategory(p), activityQuickCategories[label]);
    }
    expect(
      welfareActivityCategory({...raw, 'category': '심리지원', 'title': '마음 돌봄'}),
      '건강·운동',
    );
  });
  test(
    'coordinates match center names and radii exclude distant or unknown data',
    () {
      final pref = {
        'lat': 37.5064542,
        'lng': 126.9513983,
        'radius_km': 1,
        'interests': ['건강·운동'],
      };
      final p = welfareCatalogItem(raw, centers, pref);
      expect(p['distance_km'], 0);
      expect(p['telephone'], '02-000-0000');
      expect(welfareMatchesPreferences(p, pref), true);
      expect(
        welfareMatchesPreferences({...p, 'distance_km': 1.01}, pref),
        false,
      );
      expect(
        welfareMatchesPreferences({...p, 'distance_km': null}, pref),
        false,
      );
      expect(
        welfareMatchesPreferences(
          {...p, 'distance_km': null},
          pref,
          includeUnlocated: true,
        ),
        true,
      );
      expect(p.containsKey('status'), false);
      expect(p.containsKey('enrolled'), false);
      final ambiguous = welfareCatalogItem(raw, [
        ...centers,
        {...centers.first, 'lat': 36.0},
      ], pref);
      expect(ambiguous['lat'], isNull);
      expect(ambiguous['distance_km'], isNull);
    },
  );
  test(
    'coordinate request failure preserves phone and visit program discovery',
    () async {
      final client = SupabaseClient(
        'https://catalog.invalid',
        'offline-test',
        httpClient: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path.endsWith('welfare_programs')
                  ? [raw]
                  : {'message': 'offline'},
            ),
            r.url.path.endsWith('welfare_programs') ? 200 : 503,
            headers: {'content-type': 'application/json'},
            request: r,
          ),
        ),
      );
      final list = await ActivityWelfareCatalog(client).load(null);
      expect(list.single['title'], '은빛 요가');
      expect(list.single['lat'], isNull);
      await client.dispose();
    },
  );
  testWidgets(
    'external results are searchable and open informational detail without enrollment',
    (t) async {
      final r = FakeActivityRepository();
      r.welfarePrograms.add(welfareCatalogItem(raw, centers, null));
      await mount(
        t,
        ActivitySectionPage(
          section: ActivitySection.programs,
          repository: r,
          initialCategory: '건강·운동',
          initialQuery: '은빛',
        ),
      );
      expect(find.text('은빛 요가'), findsOneWidget);
      expect(find.text('전화·방문 신청'), findsOneWidget);
      expect(find.text('모집 마감'), findsNothing);
      expect(find.text('무료 · 재료비 별도'), findsOneWidget);
      await tap(t, find.text('은빛 요가'));
      expect(find.byType(ActivityWelfareDetailPage), findsOneWidget);
      expect(find.text('기관에 전화 문의'), findsOneWidget);
      expect(find.text('신청하기'), findsNothing);
      await visible(t, find.text('시설 위치 지도 보기'));
      expect(r.applyCalls, 0);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets(
    'unlocated institution programs remain discoverable separately from radius recommendations',
    (t) async {
      final r = FakeActivityRepository()..programs.clear();
      r.pref = {
        'lat': 37.5,
        'lng': 127.0,
        'radius_km': 1,
        'interests': ['건강·운동'],
      };
      r.welfarePrograms.add(welfareCatalogItem(raw, [], r.pref));
      await mount(
        t,
        ActivitySectionPage(section: ActivitySection.find, repository: r),
      );
      await visible(t, find.text('거리 확인이 필요한 기관 안내'));
      expect(find.text('기관 안내 프로그램 1개'), findsNothing);
      await visible(t, find.text('은빛 요가'));
      expect(find.byType(ActivityListingCard), findsWidgets);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets(
    'three narrow weekly reward badges stay on one line at large text scale',
    (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(320, 640);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      await mount(
        t,
        Row(
          children: [
            for (final text in ['+ 10 EXP', '+ 100 P', '+ 30 EXP'])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: PetPill(text),
                ),
              ),
          ],
        ),
        scale: 1.5,
      );
      for (final text in ['+ 10 EXP', '+ 30 EXP']) {
        final p = t.renderObject<RenderParagraph>(find.text(text));
        final boxes = p.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        expect(boxes.map((box) => box.top).toSet(), hasLength(1));
        final widget = t.widget<Text>(find.text(text));
        expect(widget.softWrap, false);
      }
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
}

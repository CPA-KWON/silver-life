import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/activity/activity_welfare_catalog.dart';
import 'package:silver_life/activity/activity_welfare_detail.dart';
import 'package:silver_life/core/public_source.dart';
import 'package:silver_life/facility/welfare_program_status.dart';

import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  test('deadline closes on Korean midnight, not host timezone', () {
    final offer = {'registration_ends_on': '2026-10-30'};
    expect(
      welfareProgramVisible(offer, now: DateTime.parse('2026-10-30T14:59:59Z')),
      true,
    );
    expect(
      welfareProgramVisible(offer, now: DateTime.parse('2026-10-30T15:00:00Z')),
      false,
    );
    expect(
      welfareProgramVisible({
        'source_status': 'closed',
        'registration_ends_on': '2099-12-31',
      }),
      false,
    );
    expect(
      welfareProgramVisible({'registration_starts_on': '2099-12-31'}),
      false,
    );
    expect(welfareProgramVisible({'program_ends_on': '2020-01-01'}), false);
    expect(welfareProgramVisible({'schedule': '상시 · 기관 문의'}), true);
  });

  test(
    'public source links cannot launch scripts, insecure or credential URLs',
    () {
      for (final value in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'http://example.com',
        'https://user:password@example.com',
        null,
      ]) {
        expect(publicSourceUri(value), isNull);
      }
      expect(
        publicSourceUri(
          'https://www.50plus.or.kr/djc/education-detail.do?id=77666438',
        )?.host,
        'www.50plus.or.kr',
      );
    },
  );

  test(
    'offsite programs never inherit organizer coordinates or enrollment status',
    () {
      final p = welfareCatalogItem(
        {
          'id': 1,
          'facility_name': '동작50플러스센터',
          'title': '외부 실습',
          'category': '생활·기술',
          'location_is_offsite': true,
          'place': '외부실습교육장(7호선 군자역 인근)',
          'contact_phone': '02-2169-8705',
          'source_url':
              'https://www.50plus.or.kr/djc/education-detail.do?id=77913389',
        },
        [
          {
            'name': '동작50플러스센터',
            'lat': 37.51,
            'lng': 126.94,
            'address': '노량진로 140',
          },
        ],
        {'lat': 37.51, 'lng': 126.94},
      );
      expect(p['lat'], isNull);
      expect(p['distance_km'], isNull);
      expect(p['place_name'], contains('군자역'));
      expect(p['telephone'], '02-2169-8705');
      expect(p['application_method'], 'external');
      expect(p.containsKey('enrolled'), false);
      expect(p['category'], '생활·기술');
    },
  );

  test(
    'expired courses disappear from discovery but remain in saved catalog',
    () async {
      final client = SupabaseClient(
        'https://catalog.invalid',
        'test',
        httpClient: MockClient(
          (r) async => http.Response(
            jsonEncode(
              r.url.path.endsWith('welfare_programs')
                  ? [
                      {
                        'id': 1,
                        'facility_name': '동작50플러스센터',
                        'title': '마감 강좌',
                        'source_status': 'closed',
                      },
                      {
                        'id': 2,
                        'facility_name': '동작50플러스센터',
                        'title': '기존 상시 안내',
                      },
                    ]
                  : [],
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: r,
          ),
        ),
      );
      expect(
        (await ActivityWelfareCatalog(client).load(null))
            .map((p) => p['title']),
        ['기존 상시 안내'],
      );
      expect(
        (await ActivityWelfareCatalog(
          client,
        ).load(null, includeClosed: true)).length,
        2,
      );
      await client.dispose();
    },
  );

  testWidgets(
    'external detail shows official source and no in-app enrollment promise',
    (t) async {
      final p = welfareCatalogItem(
        {
          'id': 77,
          'facility_name': '동작50플러스센터',
          'title': '공식 교육',
          'source_url':
              'https://www.50plus.or.kr/djc/education-detail.do?id=77666438',
          'source_verified_at': '2026-10-30T10:00:00+09:00',
          'contact_phone': '02-2169-8704',
          'registration_ends_on': '2099-12-31',
          'how_to_apply': '기관 공식 홈페이지에서 수강신청',
        },
        [],
        null,
      );
      await mount(t, ActivityWelfareDetailPage(program: p));
      expect(find.text('기관 홈페이지 신청'), findsOneWidget);
      expect(find.text('기관 홈페이지 확인'), findsOneWidget);
      expect(find.text('신청하기'), findsNothing);
      await visible(t, find.text('원문에서 모집 상태 확인'));
      expect(find.text('정보 확인 2026-10-30 · 잔여석은 원문 확인'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );

  test('import snapshot has unique real source keys, current deadlines and no agency/reward rows', () {
    final data = jsonDecode(
      File('data/public_programs_20261030.json').readAsStringSync(),
    ) as Map;
    final rows = List<Map<String, dynamic>>.from(
      (data['programs'] as List).map((p) => Map<String, dynamic>.from(p)),
    );
    expect(rows.length, 162);
    expect(
      rows.map((p) => '${p['source']}:${p['source_id']}').toSet().length,
      rows.length,
    );
    for (final p in rows) {
      expect(p['source_status'], 'open');
      expect(p['source_url'], startsWith('https://www.50plus.or.kr/'));
      expect(
        '${p['registration_ends_on']}'.compareTo('2026-10-30'),
        greaterThanOrEqualTo(0),
      );
      expect(p.containsKey('org_id'), false);
      expect(p.containsKey('reward'), false);
    }
  });
}

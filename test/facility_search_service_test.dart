import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silver_life/facility/naver_local_search.dart';

http.Response results() => http.Response(
  jsonEncode({
    'items': [
      for (final offset in [20000, 0])
        {
          'title': '<b>병원</b>',
          'category': '병원',
          'roadAddress': '',
          'address': '서울특별시 중구',
          'telephone': '02-000-0000',
          'mapx': '${1269780000 + offset}',
          'mapy': '375665000',
        },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  Future<List<FacilityResult>> search(
    FacilitySearchService service, [
    String category = '병원',
  ]) => service.search(category: category, lat: 37.5665, lng: 126.978);

  test(
    'same concurrent search shares one geocode and one HTTP request',
    () async {
      final area = Completer<String>();
      var geocodes = 0;
      var requests = 0;
      final service = testService(
        resolveArea: (_, _) {
          geocodes++;
          return area.future;
        },
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'POST');
          expect(request.url.host, 'supabase.invalid');
          expect(request.url.path, '/functions/v1/facility-search');
          final sent = jsonDecode(request.body) as Map;
          expect(sent['query'], '중구 병원');
          expect(sent['nearby'], {
            'keyword': '병원',
            'lat': 37.5665,
            'lng': 126.978,
            'group': 'HP8',
          });
          expect(request.headers['Authorization'], 'Bearer offline-session');
          expect(request.headers, isNot(contains('X-NCP-APIGW-API-KEY')));
          return results();
        }),
      );
      addTearDown(service.close);
      final first = search(service);
      final second = search(service);
      area.complete('중구');
      final lists = await Future.wait([first, second]);
      expect(geocodes, 1);
      expect(requests, 1);
      expect(lists.first, same(lists.last));
      expect(lists.first.first.name, '병원');
      expect(lists.first.first.address, '서울특별시 중구');
      expect(
        lists.first.first.distanceMeters,
        lessThan(lists.first.last.distanceMeters),
      );
      expect(await search(service), same(lists.first));
      expect(requests, 1);
    },
  );

  test(
    'hospital and pharmacy share address lookup but retain distinct queries',
    () async {
      final area = Completer<String>();
      var geocodes = 0;
      final queries = <String>[];
      final service = testService(
        resolveArea: (_, _) {
          geocodes++;
          return area.future;
        },
        client: MockClient((request) async {
          queries.add((jsonDecode(request.body) as Map)['query'] as String);
          return results();
        }),
      );
      addTearDown(service.close);
      final pending = Future.wait([search(service), search(service, '약국')]);
      area.complete('중구');
      await pending;
      expect(geocodes, 1);
      expect(queries, unorderedEquals(['중구 병원', '중구 약국']));
    },
  );

  test(
    'cache expires after five minutes and does not merge distant positions',
    () async {
      var now = DateTime(2026, 10, 16);
      var requests = 0;
      var geocodes = 0;
      final service = testService(
        now: () => now,
        resolveArea: (_, _) async {
          geocodes++;
          return '중구';
        },
        client: MockClient((_) async {
          requests++;
          return results();
        }),
      );
      addTearDown(service.close);
      await search(service);
      now = now.add(const Duration(minutes: 4));
      await search(service);
      expect(requests, 1);
      now = now.add(const Duration(minutes: 1));
      await search(service);
      expect(requests, 2);
      expect(geocodes, 2);
      await service.search(category: '병원', lat: 37.5, lng: 127.0);
      expect(requests, 3);
    },
  );

  test(
    '429 stays distinguishable and a failed request can be retried',
    () async {
      var requests = 0;
      final service = testService(
        resolveArea: (_, _) async => '중구',
        client: MockClient(
          (_) async => ++requests == 1 ? http.Response('', 429) : results(),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        search(service),
        throwsA(isA<FacilityRateLimitException>()),
      );
      expect(await search(service), hasLength(2));
      expect(requests, 2);
    },
  );

  test(
    'a synchronous geocoder failure does not poison later local searches',
    () async {
      var calls = 0;
      final queries = <String>[];
      final service = testService(
        resolveArea: (_, _) {
          if (++calls == 1) throw StateError('temporary geocoder failure');
          return Future.value('중구');
        },
        client: MockClient((request) async {
          queries.add((jsonDecode(request.body) as Map)['query'] as String);
          return results();
        }),
      );
      addTearDown(service.close);
      await search(service);
      await search(service);
      expect(queries, ['병원', '중구 병원']);
    },
  );

  testWidgets('slow geocoder falls back after its deadline', (tester) async {
    final area = Completer<String>();
    final queries = <String>[];
    final service = testService(
      resolveArea: (_, _) => area.future,
      client: MockClient((request) async {
        queries.add((jsonDecode(request.body) as Map)['query'] as String);
        return results();
      }),
    );
    addTearDown(service.close);
    final pending = search(service);
    await tester.pump(const Duration(seconds: 3));
    expect(await pending, hasLength(2));
    expect(queries, ['병원']);
    area.complete('중구');
  });

  testWidgets('HTTP deadline aborts a stalled request and releases retry', (
    tester,
  ) async {
    final client = _StalledClient();
    final service = testService(
      client: client,
      resolveArea: (_, _) async => '중구',
    );
    addTearDown(service.close);
    final first = search(service);
    final expectation = expectLater(first, throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await expectation;
    expect(client.aborted, isTrue);
    client.respond = true;
    expect(await search(service), hasLength(2));
  });

  test(
    'missing server setup is distinct from network and server outages',
    () async {
      for (final response in [
        http.Response(
          jsonEncode({'error': '시설 검색을 준비 중입니다.'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
        http.Response(jsonEncode({'code': 'SEARCH_NOT_CONFIGURED'}), 503),
        http.Response('', 404),
      ]) {
        final service = testService(
          resolveArea: (_, _) async => '중구',
          client: MockClient((_) async => response),
        );
        addTearDown(service.close);
        await expectLater(
          search(service),
          throwsA(isA<FacilitySearchNotReadyException>()),
        );
      }
      expect(
        facilitySearchErrorMessage(const FacilitySearchNotReadyException()),
        contains('경로당'),
      );
      expect(
        facilitySearchErrorMessage(const FacilitySearchNotReadyException()),
        isNot(contains('인터넷')),
      );
    },
  );
  test(
    'expired login is not reported as an internet connection failure',
    () async {
      for (final status in [401, 403]) {
        final service = testService(
          resolveArea: (_, _) async => '중구',
          client: MockClient((_) async => http.Response('', status)),
        );
        addTearDown(service.close);
        await expectLater(
          search(service),
          throwsA(isA<FacilitySearchAuthException>()),
        );
      }
      expect(
        facilitySearchErrorMessage(const FacilitySearchAuthException()),
        contains('로그인'),
      );
    },
  );
  test(
    'unavailable server responses keep diagnostics private and permit retry',
    () async {
      var calls = 0;
      final service = testService(
        resolveArea: (_, _) async => '중구',
        client: MockClient(
          (_) async => ++calls == 1
              ? http.Response('<html>private upstream details</html>', 503)
              : results(),
        ),
      );
      addTearDown(service.close);
      await expectLater(
        search(service),
        throwsA(isA<FacilitySearchServerException>()),
      );
      expect(await search(service), hasLength(2));
      expect(calls, 2);
      expect(
        facilitySearchErrorMessage(http.ClientException('offline')),
        contains('인터넷'),
      );
    },
  );

  test('raw error bodies are not displayed to users', () async {
    final service = testService(
      resolveArea: (_, _) async => '중구',
      client: MockClient(
        (_) async => http.Response('internal diagnostic data', 503),
      ),
    );
    addTearDown(service.close);
    try {
      await search(service);
      fail('503 should fail');
    } catch (error) {
      expect(error, isA<FacilitySearchServerException>());
      expect(facilitySearchErrorMessage(error), isNot(contains('인터넷')));
      expect(error.toString(), isNot(contains('internal diagnostic data')));
    }
  });

  http.Response kakao() => http.Response(
    jsonEncode({
      'source': 'kakao',
      'places': [
        for (final (name, lng) in [('먼약국', 126.99), ('가까운약국', 126.9781)])
          {
            'name': name,
            'category': '약국',
            'address': '서울 중구 세종대로 110',
            'telephone': '02-1',
            'lat': 37.5665,
            'lng': lng,
          },
      ],
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('Kakao results are nearest-first, live-only and never cached', () async {
    var requests = 0;
    final service = testService(
      resolveArea: (_, _) async => '중구',
      client: MockClient((_) async {
        requests++;
        return kakao();
      }),
    );
    addTearDown(service.close);
    final list = await search(service, '약국');
    expect(list.map((r) => r.name), ['가까운약국', '먼약국']);
    expect(list.every((r) => r.liveOnly), isTrue);
    await search(service, '약국');
    expect(requests, 2);
  });

  test('saving a Kakao place swaps in the matching NAVER place', () async {
    final queries = <Object?>[];
    final service = testService(
      client: MockClient((request) async {
        queries.add(jsonDecode(request.body));
        return http.Response(
          jsonEncode({
            'items': [
              for (final (title, x) in [
                ('다른약국', '1269781000'),
                ('<b>가까운</b> 약국', '1269781000'),
              ])
                {
                  'title': title,
                  'category': '약국',
                  'roadAddress': '서울특별시 중구 세종대로 110',
                  'address': '',
                  'telephone': '02-2',
                  'mapx': x,
                  'mapy': '375665000',
                },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(service.close);
    const place = FacilityResult(
      name: '가까운약국',
      category: '약국',
      address: '서울 중구 세종대로 110',
      telephone: '02-1',
      lat: 37.5665,
      lng: 126.9781,
      distanceMeters: 12,
      liveOnly: true,
    );
    final stored = await service.findStorable(place);
    expect(queries, [
      {'query': '서울 중구 가까운약국'},
    ]);
    expect(stored.name, '가까운 약국');
    expect(stored.address, '서울특별시 중구 세종대로 110');
    expect(stored.liveOnly, isFalse);
  });

  test('a Kakao place without a nearby NAVER match cannot be saved', () async {
    final service = testService(client: MockClient((_) async => results()));
    addTearDown(service.close);
    const place = FacilityResult(
      name: '없는약국',
      category: '약국',
      address: '서울 중구 세종대로 110',
      telephone: '',
      lat: 37.5665,
      lng: 126.978,
      distanceMeters: 0,
      liveOnly: true,
    );
    await expectLater(
      service.findStorable(place),
      throwsA(isA<FacilityNotStorableException>()),
    );
  });
}

class _StalledClient extends http.BaseClient {
  bool aborted = false;
  bool respond = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (respond) {
      final response = results();
      return http.StreamedResponse(Stream.value(response.bodyBytes), 200);
    }
    final done = Completer<http.StreamedResponse>();
    (request as http.Abortable).abortTrigger!.then((_) {
      aborted = true;
      done.completeError(http.RequestAbortedException(request.url));
    });
    return done.future;
  }
}

FacilitySearchService testService({
  http.Client? client,
  Future<String> Function(double, double)? resolveArea,
  DateTime Function()? now,
  Duration geocodingTimeout = const Duration(seconds: 3),
  Duration requestTimeout = const Duration(seconds: 10),
}) => FacilitySearchService(
  client: client,
  resolveArea: resolveArea,
  now: now,
  geocodingTimeout: geocodingTimeout,
  requestTimeout: requestTimeout,
  supabaseUrl: 'https://supabase.invalid',
  supabaseAnonKey: 'public-test-key',
  accessToken: () => 'offline-session',
);

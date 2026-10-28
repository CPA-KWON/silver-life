import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:silver_life/facility/facility_distance.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silver_life/app_theme.dart';
import 'package:silver_life/facility/facility_search_page.dart';
import 'package:silver_life/facility/naver_local_search.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const facility = FacilityResult(
  id: '22222222-2222-4222-8222-222222222222',
  name: '테스트 시설',
  category: '병원',
  address: '서울특별시 중구 테스트로',
  telephone: '',
  lat: 37.5,
  lng: 127,
  distanceMeters: 100,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<http.Response> Function(http.Request) respond;
  late Supabase supabase;
  final requests = <http.Request>[];

  setUp(() async {
    requests.clear();
    respond = (_) async =>
        jsonResponse('[]', 200, headers: {'content-type': 'application/json'});
    supabase = await Supabase.initialize(
      url: 'https://supabase.invalid',
      publishableKey: 'offline-test-key',
      debug: false,
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: _MemoryStorage(),
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUri: false,
      ),
      realtimeClientOptions: RealtimeClientOptions(
        transport: (_, _) =>
            throw StateError('No real sockets in offline tests'),
        timeout: const Duration(milliseconds: 10),
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
    );
    // A deliberately unsigned, local-only test session. No real account or key.
    final payload = base64Url
        .encode(
          utf8.encode(
            jsonEncode({
              'sub': '11111111-1111-4111-8111-111111111111',
              'exp':
                  DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            }),
          ),
        )
        .replaceAll('=', '');
    await supabase.client.auth.setInitialSession(
      jsonEncode({
        'access_token': 'e30.$payload.test',
        'token_type': 'bearer',
        'expires_in': 3600,
        'refresh_token': 'offline-refresh',
        'user': {
          'id': '11111111-1111-4111-8111-111111111111',
          'aud': 'authenticated',
          'app_metadata': {},
          'user_metadata': {},
          'created_at': '2026-01-01T00:00:00Z',
        },
      }),
    );
  });
  tearDown(() async => supabase.dispose());

  Widget page([FacilityResult result = facility, double textScale = 1]) =>
      MaterialApp(
        theme: seniorFriendlyTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FacilityDetailPage(result: result, onClose: () {}),
      );

  test('distance labels never round a nearby facility to 0.0km', () {
    expect(facilityDistanceLabel(0), contains('10m 이내'));
    expect(facilityDistanceLabel(76), contains('80m'));
    expect(facilityDistanceLabel(2300), contains('2.3km'));
    expect(facilityDistanceLabel(double.nan), contains('현재 위치를 확인'));
    expect(facilityDistanceLabel(null), isNot(contains('0.0')));
  });

  testWidgets(
    'facility distance uses user GPS rather than stored search-center distance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FacilityDetailPage(
            result: facility,
            onClose: () {},
            positionLoader: () async => Position(
              longitude: 127,
              latitude: 37.6,
              timestamp: DateTime.now(),
              accuracy: 10,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 0,
              headingAccuracy: 0,
              speed: 0,
              speedAccuracy: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('현재 위치에서 약 11.1km · 직선거리'), findsOneWidget);
      expect(find.textContaining('0.1km'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 20));
    },
  );
  testWidgets('missing GPS does not claim zero distance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FacilityDetailPage(
          result: facility,
          onClose: () {},
          positionLoader: () async => throw StateError('GPS unavailable'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('현재 위치를 확인하면 거리를 볼 수 있어요'), findsOneWidget);
    expect(find.textContaining('0.0km'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets(
    'checkins and meetups start together without waiting for one another',
    (tester) async {
      final checkins = Completer<http.Response>();
      final meetups = Completer<http.Response>();
      respond = (request) async {
        if (request.url.path.endsWith('/facility_presence')) {
          return checkins.future;
        }
        if (request.url.path.endsWith('/posts')) return meetups.future;
        return jsonResponse(
          request.url.path.endsWith('/facility_presence')
              ? '{"count":0,"checked_in":false}'
              : '[]',
          200,
        );
      };
      await tester.pumpWidget(page());
      await tester.pump();
      expect(
        requests.where((r) => r.url.path.endsWith('/facility_presence')),
        hasLength(1),
      );
      expect(
        requests.where((r) => r.url.path.endsWith('/posts')),
        hasLength(1),
      );
      expect(supabase.client.getChannels(), hasLength(1));
      final query = requests
          .singleWhere((r) => r.url.path.endsWith('/posts'))
          .url
          .queryParameters;
      expect(query['facility_id'], 'eq.${facility.id}');
      expect(query['event_at'], startsWith('gte.'));
      meetups.complete(jsonResponse('[]', 200));
      checkins.complete(jsonResponse('{"count":0,"checked_in":false}', 200));
      await tester.pump();
      await tester.pump();
      expect(find.text('현재 0명 있음'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
      expect(supabase.client.getChannels(), isEmpty);
    },
  );

  testWidgets(
    'network failure offers retry without losing facility information',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var failing = true;
      respond = (request) async => failing
          ? jsonResponse(
              '{"message":"temporary failure","code":"test_error"}',
              400,
            )
          : jsonResponse(
              request.url.path.endsWith('/facility_presence')
                  ? '{"count":0,"checked_in":false}'
                  : '[]',
              200,
            );
      await tester.pumpWidget(page(facility, 1.3));
      await tester.pump();
      await tester.pump();
      expect(find.text('시설 정보를 불러오지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('테스트 시설'), findsWidgets);
      failing = false;
      await tester.ensureVisible(find.text('다시 시도'));
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();
      expect(find.text('시설 정보를 불러오지 못했어요. 다시 시도해 주세요.'), findsNothing);
      expect(find.text('현재 0명 있음'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 20));
    },
  );

  testWidgets(
    'closing during facility upsert cannot create a late realtime channel',
    (tester) async {
      final upsert = Completer<http.Response>();
      respond = (request) async => request.url.path.endsWith('/ensure_facility')
          ? upsert.future
          : jsonResponse(
              request.url.path.endsWith('/facility_presence')
                  ? '{"count":0,"checked_in":false}'
                  : '[]',
              200,
            );
      const external = FacilityResult(
        name: '외부 검색 시설',
        category: '병원',
        address: '서울특별시 중구 테스트로',
        telephone: '',
        lat: 37.5,
        lng: 127,
        distanceMeters: 0,
      );
      await tester.pumpWidget(page(external));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      upsert.complete(jsonResponse(jsonEncode(facility.id), 200));
      await tester.pump();
      await tester.pump();
      expect(supabase.client.getChannels(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

http.Response jsonResponse(
  String body,
  int status, {
  Map<String, String>? headers,
}) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

class _MemoryStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

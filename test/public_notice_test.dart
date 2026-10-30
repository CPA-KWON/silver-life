import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/core/neighborhood_region.dart';
import 'package:silver_life/notices/notice_pages.dart';
import 'package:silver_life/notices/notice_repository.dart';

import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

const centerA = {
  'institution_name': '상도종합사회복지관',
  'region_sido': '서울특별시',
  'region_sigungu': '동작구',
  'address': '서울특별시 동작구 상도로39가길 7',
};
const centerB = {
  'institution_name': '흑석종합사회복지관',
  'region_sido': '서울특별시',
  'region_sigungu': '동작구',
  'address': '서울특별시 동작구 흑석한강로 13',
};
Map<String, dynamic> sourceNotice(Map<String, dynamic> center, String id) =>
    publicNoticeData({
      ...center,
      'id': id,
      'institution_kind': '복지관',
      'title': '${center['institution_name']} 교육 안내',
      'summary': '자세한 사항은 기관 원문에서 확인해 주세요.',
      'published_on': '2026-10-30',
      'source_url': 'https://example.org/notice/$id',
      'source_verified_at': '2026-10-30T01:00:00Z',
      'published': true,
    });

class UsualNoticeFake extends NoticeRepository {
  Map<String, dynamic>? selected;
  bool failSave = false;
  int saves = 0;
  @override
  Future<NoticeData?> preferredInstitution() async => selected;
  @override
  Future<List<NoticeData>> institutions() async => [centerA, centerB];
  @override
  Future<void> selectInstitution(NoticeData institution) async {
    saves++;
    if (failSave) throw StateError('offline');
    selected = institution;
  }

  @override
  Future<List<NoticeData>> feed() async => [
    sourceNotice(centerA, 'a'),
    sourceNotice(centerB, 'b'),
  ];
  @override
  Future<List<NoticeData>> publicFeed({
    bool archive = false,
    bool allRegions = false,
    NeighborhoodRegion? region,
    NoticeData? institution,
  }) async => [
    for (final c in [centerA, centerB])
      if (institution == null ||
          c['institution_name'] == institution['institution_name'])
        sourceNotice(c, c == centerA ? 'a' : 'b'),
  ];
  @override
  Future<NoticeData> detail(String id) async =>
      (await feed()).firstWhere((n) => n['id'] == id);
}

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'home entry selects one institution and opens only its public notices',
    (t) async {
      final repo = UsualNoticeFake();
      await mount(t, MyInstitutionNoticeCard(repository: repo));
      await tap(t, find.text('내 복지관 지정하기'));
      expect(find.text('내 복지관으로 지정'), findsOneWidget);
      await fill(t, '복지관 이름·지역 검색', '흑석');
      expect(find.text('상도종합사회복지관'), findsNothing);
      await tap(t, find.text('흑석종합사회복지관'));
      await tap(t, find.text('내 복지관으로 지정'));
      expect(repo.selected?['institution_name'], '흑석종합사회복지관');
      expect(repo.saves, 1);
      expect(find.text('내 복지관 · 흑석종합사회복지관'), findsOneWidget);
      await tap(t, find.text('우리 복지관 소식 보기'));
      expect(find.text('흑석종합사회복지관 교육 안내'), findsOneWidget);
      expect(find.text('상도종합사회복지관 교육 안내'), findsNothing);
      await tap(t, find.text('흑석종합사회복지관 교육 안내'));
      expect(find.text('기관 원문에서 자세히 보기'), findsOneWidget);
      expect(find.text('원문 수집'), findsOneWidget);
      expect(find.text('공식'), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );

  testWidgets('failed selection retains the chosen institution for retry', (
    t,
  ) async {
    final repo = UsualNoticeFake()..failSave = true;
    await mount(t, NoticeInstitutionPicker(repository: repo));
    await tap(t, find.text('상도종합사회복지관'));
    await tap(t, find.text('내 복지관으로 지정'));
    expect(find.text('내 복지관을 저장하지 못했어요'), findsOneWidget);
    await tap(t, find.text('확인'));
    expect(find.text('상도종합사회복지관'), findsOneWidget);
    expect(repo.selected, isNull);
    expect(t.takeException(), isNull);
    await finish(t);
  });

  test('repository filters a selected institution independently of current GPS district', () async {
    final requests = <http.Request>[];
    var preferenceGets = 0;
    final client = SupabaseClient(
      'https://notice.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        requests.add(r);
        final name = r.url.pathSegments.last;
        Object? body = [];
        if (name == 'my_notice_institutions' && r.method == 'GET') {
          preferenceGets++;
          body = [
            {'user_id': FakeBackend.user, ...centerB},
          ];
        }
        if (name == 'public_institution_notices') {
          body = [
            {
              ...centerB,
              'id': 'b',
              'published_on': '2026-10-30',
              'title': '교육',
              'summary': '원문 확인',
            },
          ];
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
    await client.auth.setInitialSession(jsonEncode(backend.session));
    final repo = NoticeRepository(
      supabase: client,
      regionResolver: NeighborhoodRegionResolver(
        positionLoader: () async =>
            throw StateError('GPS must not be used for selected institution'),
      ),
    );
    await Future.wait([
      repo.preferredInstitution(),
      repo.preferredInstitution(),
    ]);
    expect(preferenceGets, 1);
    final feed = await repo.homeFeed();
    expect(feed.single['id'], 'public-notice:b');
    final query = requests.last.url.queryParameters;
    expect(query['institution_name'], 'eq.흑석종합사회복지관');
    expect(query['region_sigungu'], 'eq.동작구');
    await repo.selectInstitution(centerA);
    final posted = jsonDecode(requests.last.body) as Map;
    expect(posted['user_id'], FakeBackend.user);
    expect(posted['institution_name'], '상도종합사회복지관');
    expect(
      requests.any((r) => r.url.path.contains('activity_org_members')),
      false,
    );
    await client.dispose();
  });

  test('public archive pages load beyond row caps and keep genuine publication dates', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://notice.invalid',
      'test',
      httpClient: MockClient((r) async {
        calls++;
        final items = List.generate(
          calls == 1 ? 500 : 1,
          (i) => {
            'id': '$calls-$i',
            'institution_name': '공개 기관',
            'published_on': '2025-03-11',
            'summary': '원문 확인',
            'title': '기존 안내',
          },
        );
        expect(r.url.queryParameters.containsKey('or'), true);
        return http.Response(
          jsonEncode(items),
          200,
          headers: {'content-type': 'application/json'},
          request: r,
        );
      }),
    );
    final repo = NoticeRepository(supabase: client);
    final rows = await repo.publicFeed(archive: true, allRegions: true);
    expect(rows.length, 501);
    expect(calls, 2);
    expect(rows.first['published_at'], '2025-03-11T00:00:00+09:00');
    expect(rows.first['is_public_source'], true);
    expect(rows.first['important'], false);
    await client.dispose();
  });
}

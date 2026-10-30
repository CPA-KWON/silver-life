import 'dart:convert';

import 'package:flutter/material.dart';
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
String kstDay(int daysAgo) => DateTime.now()
    .toUtc()
    .add(const Duration(hours: 9))
    .subtract(Duration(days: daysAgo))
    .toIso8601String()
    .split('T')
    .first;
Map<String, dynamic> sourceNotice(
  Map<String, dynamic> center,
  String id, {
  int daysAgo = 0,
  String? title,
}) => publicNoticeData({
  ...center,
  'id': id,
  'institution_kind': '복지관',
  'title': title ?? '${center['institution_name']} 교육 안내',
  'summary': '자세한 사항은 기관 원문에서 확인해 주세요.',
  'published_on': kstDay(daysAgo),
  'source_url': 'https://example.org/notice/$id',
  'source_verified_at': '2026-10-30T01:00:00Z',
  'published': true,
});

class UsualNoticeFake extends NoticeRepository {
  Map<String, dynamic>? selected;
  bool failSave = false;
  int saves = 0;
  int ageDays = 0;
  final archived = <NoticeData>[], extra = <NoticeData>[];
  @override
  Future<NoticeData?> preferredInstitution() async => selected;
  @override
  Future<List<NoticeData>> institutions() async => [centerA, centerB];
  @override
  Future<void> selectInstitution(NoticeData institution) async {
    saves++;
    if (failSave) throw StateError('offline');
    selected = institution;
    preferenceRevision++;
  }

  @override
  Future<NeighborhoodRegion> currentRegion() async => defaultNeighborhood;
  @override
  Future<List<NoticeData>> feed() async => [
    sourceNotice(centerA, 'a', daysAgo: ageDays),
    sourceNotice(centerB, 'b', daysAgo: ageDays),
    ...extra,
  ];
  @override
  Future<List<NoticeData>> browse({
    bool archive = false,
    bool allRegions = false,
  }) async => archive ? archived : feed();
  @override
  Future<List<NoticeData>> institutionFeed(
    NoticeData institution, {
    bool archive = false,
  }) async => [
    for (final n in archive ? archived : await feed())
      if (n['org_name'] == institution['institution_name']) n,
  ];
  @override
  Future<NoticeData> detail(String id) async =>
      [...await feed(), ...archived].firstWhere((n) => n['id'] == id);
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
    'home card selects one institution and opens only its public notices',
    (t) async {
      final repo = UsualNoticeFake();
      await mount(t, MyInstitutionNoticeCard(repository: repo));
      expect(find.text('자주 가는 복지관 소식을 모아보세요'), findsOneWidget);
      await tap(t, find.text('내 복지관 지정하기'));
      expect(find.text('내 복지관 지정'), findsOneWidget);
      expect(find.text('복지관을 골라 주세요'), findsOneWidget);
      expect(find.text('복지관 2곳'), findsOneWidget);
      await fill(t, '복지관 이름·지역 검색', '흑석');
      expect(find.text('상도종합사회복지관'), findsNothing);
      await tap(t, find.text('흑석종합사회복지관'));
      await tap(t, find.text('내 복지관으로 지정'));
      expect(repo.selected?['institution_name'], '흑석종합사회복지관');
      expect(repo.saves, 1);
      expect(find.text('내 복지관으로 지정했어요'), findsOneWidget);
      expect(find.text('흑석종합사회복지관'), findsOneWidget);
      expect(find.text('새 소식 1'), findsOneWidget);
      expect(find.text('흑석종합사회복지관 교육 안내'), findsOneWidget);
      await tap(t, find.text('소식 보기'));
      expect(find.text('내 복지관 소식'), findsOneWidget);
      expect(find.text('최근 일주일'), findsOneWidget);
      expect(find.text('흑석종합사회복지관 교육 안내'), findsOneWidget);
      expect(find.text('상도종합사회복지관 교육 안내'), findsNothing);
      await tap(t, find.text('흑석종합사회복지관 교육 안내'));
      expect(find.text('공지'), findsOneWidget);
      expect(find.text('홈페이지 원문'), findsOneWidget);
      expect(find.text('기관 직접 등록'), findsNothing);
      expect(find.textContaining('접수 여부는 원문에서'), findsOneWidget);
      await tap(t, find.text('기관 원문에서 자세히 보기'));
      expect(find.text('기관 홈페이지로 이동해요'), findsOneWidget);
      expect(find.text('뒤로 가기를 누르면 앱으로'), findsOneWidget);
      await tap(t, find.text('취소'));
      expect(find.text('기관 홈페이지로 이동해요'), findsNothing);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );

  testWidgets('home card without recent notices points to the full list', (
    t,
  ) async {
    final repo = UsualNoticeFake()
      ..selected = centerA
      ..ageDays = 10;
    await mount(t, MyInstitutionNoticeCard(repository: repo));
    expect(find.text('상도종합사회복지관'), findsOneWidget);
    expect(find.text('새 소식이 없어요\n지난 공지는 소식 보기에서 볼 수 있어요'), findsOneWidget);
    expect(find.text('상도종합사회복지관 교육 안내'), findsNothing);
    await tap(t, find.text('소식 보기 ›'));
    expect(find.text('최근 일주일'), findsNothing);
    expect(find.text('상도종합사회복지관 교육 안내'), findsOneWidget);
    await finish(t);
  });

  testWidgets('long names and double-size text stay on screen', (t) async {
    const longCenter = {
      'institution_name': '서울특별시립 동작노인종합복지관 상도분관 어르신행복센터',
      'region_sido': '서울특별시',
      'region_sigungu': '동작구',
    };
    const longTitle =
        '2026년 하반기 어르신 디지털 배움터 스마트폰 활용 심화반(키오스크·모바일 뱅킹) 참여자 모집 안내';
    final repo = UsualNoticeFake()
      ..selected = longCenter
      ..extra.add(sourceNotice(longCenter, 'long', title: longTitle));
    await mount(t, MyInstitutionNoticeCard(repository: repo), scale: 2);
    expect(find.text(longCenter['institution_name']!), findsOneWidget);
    expect(find.text('새 소식 1'), findsOneWidget);
    await tap(t, find.text('소식 보기'));
    expect(find.text(longTitle), findsOneWidget);
    await tap(t, find.text(longTitle));
    expect(find.text('기관 원문에서 자세히 보기'), findsOneWidget);
    await tap(t, find.byTooltip('뒤로'));
    await tap(t, find.text('변경'));
    expect(find.text('내 복지관 변경'), findsOneWidget);
    expect(t.takeException(), isNull);
    await finish(t);
  });

  testWidgets('change mode marks the current institution and confirms', (
    t,
  ) async {
    final repo = UsualNoticeFake()..selected = centerA;
    await mount(
      t,
      Builder(
        builder: (c) => TextButton(
          onPressed: () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) =>
                  NoticeInstitutionPicker(repository: repo, current: centerA),
            ),
          ),
          child: const Text('열기'),
        ),
      ),
    );
    await tap(t, find.text('열기'));
    expect(find.text('내 복지관 변경'), findsOneWidget);
    expect(find.text('지금 내 복지관'), findsOneWidget);
    await tap(t, find.text('상도종합사회복지관'));
    expect(find.text('지금 내 복지관이에요'), findsOneWidget);
    await tap(t, find.text('흑석종합사회복지관'));
    await tap(t, find.text('이곳으로 변경'));
    expect(find.text('내 복지관을 바꿀까요?'), findsOneWidget);
    expect(find.text('바꿀 곳'), findsOneWidget);
    await tap(t, find.text('취소'));
    expect(repo.saves, 0);
    await tap(t, find.text('이곳으로 변경'));
    await tap(t, find.text('바꾸기'));
    expect(repo.selected?['institution_name'], '흑석종합사회복지관');
    expect(find.text('내 복지관을 바꿨어요'), findsOneWidget);
    expect(find.text('열기'), findsOneWidget);
    await finish(t);
  });

  testWidgets('search without results offers to clear the search', (t) async {
    await mount(t, NoticeInstitutionPicker(repository: UsualNoticeFake()));
    await fill(t, '복지관 이름·지역 검색', '상도노인복지');
    expect(find.text('찾는 복지관이 없어요'), findsOneWidget);
    await tap(t, find.text('검색어 지우기').last);
    expect(find.text('상도종합사회복지관'), findsOneWidget);
    expect(find.text('흑석종합사회복지관'), findsOneWidget);
    await finish(t);
  });

  testWidgets('empty new tab leads to past notices and other news menu', (
    t,
  ) async {
    final repo = UsualNoticeFake()
      ..selected = centerB
      ..archived.add(
        sourceNotice(centerB, 'old', daysAgo: 90, title: '추석 연휴 휴관 안내'),
      );
    await mount(t, NoticeListPage(repository: repo, preferredOnly: true));
    expect(find.text('흑석종합사회복지관 교육 안내'), findsOneWidget);
    await tap(t, find.text('지난 공지'));
    expect(find.text('추석 연휴 휴관 안내'), findsOneWidget);
    expect(find.text('새 소식'), findsOneWidget);
    await tap(t, find.text('다른 소식'));
    expect(find.text('서울 동작구의 복지관·주민센터'), findsOneWidget);
    await tap(t, find.text('전체 지역 소식'));
    expect(find.text('전체 지역 소식'), findsOneWidget);
    expect(find.text('상도종합사회복지관 교육 안내'), findsOneWidget);
    expect(find.text('흑석종합사회복지관 교육 안내'), findsOneWidget);
    await finish(t);
  });

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
    expect(find.text('내 복지관으로 지정'), findsOneWidget);
    expect(repo.selected, isNull);
    expect(t.takeException(), isNull);
    await finish(t);
  });

  test('institution names match across spacing and city prefixes', () {
    expect(institutionKey('서울시립 흑석 종합사회복지관'), '흑석종합사회복지관');
    expect(institutionKey('구립흑석종합사회복지관'), '흑석종합사회복지관');
    final now = DateTime.parse('2026-10-31T12:00:00+09:00');
    expect(
      isNewNotice({'published_at': '2026-10-25T00:00:00+09:00'}, now: now),
      true,
    );
    expect(
      isNewNotice({'published_at': '2026-10-24T00:00:00+09:00'}, now: now),
      false,
    );
  });

  test('selected institution feed uses its own district and adds its partner notices', () async {
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
              'published_on': '2026-10-28',
              'title': '교육',
              'summary': '원문 확인',
            },
          ];
        }
        if (name == 'institution_notices') {
          body = [
            {
              'id': 'own',
              'title': '체조 시간 변경',
              'body': '오전 10시 30분으로 바뀌어요.',
              'published_at': '2026-10-29T01:00:00Z',
              'activity_organizations': {
                'name': '서울시립 흑석 종합사회복지관',
                'approved': true,
              },
            },
            {
              'id': 'other',
              'title': '다른 기관 공지',
              'body': '다른 기관',
              'published_at': '2026-10-30T01:00:00Z',
              'activity_organizations': {'name': '상도종합사회복지관', 'approved': true},
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
    final both = await Future.wait([
      repo.preferredInstitution(),
      repo.preferredInstitution(),
    ]);
    expect(preferenceGets, 1);
    final feed = await repo.institutionFeed(both.first!);
    expect(feed.map((n) => n['id']), ['own', 'public-notice:b']);
    final public = requests
        .lastWhere((r) => r.url.path.endsWith('public_institution_notices'))
        .url
        .queryParameters;
    expect(public['institution_name'], 'eq.흑석종합사회복지관');
    expect(public['region_sigungu'], 'eq.동작구');
    final partner = requests
        .lastWhere((r) => r.url.path.endsWith('/institution_notices'))
        .url
        .queryParameters;
    expect(partner['region_sigungu'], 'eq.동작구');
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

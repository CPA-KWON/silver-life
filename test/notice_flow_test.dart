import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/home/home_tab.dart';
import 'package:silver_life/notices/notice_pages.dart';
import 'package:silver_life/notices/notice_repository.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

class FakeNotices extends NoticeRepository {
  final rows = <NoticeData>[];
  bool fail = false;
  int saves = 0;
  @override
  Future<NoticeData> region() async => {
    'region_sido': '서울특별시',
    'region_sigungu': '강남구',
  };
  @override
  Future<List<NoticeData>> feed() async {
    if (fail) throw StateError('offline');
    return rows.where((n) => n['published'] == true).toList();
  }

  @override
  Future<List<NoticeData>> managed() async => rows;
  @override
  Future<NoticeData> detail(String id) async =>
      rows.firstWhere((n) => n['id'] == id);
  @override
  Future<String> save(NoticeData data, {String? id}) async {
    if (fail) throw StateError('offline');
    saves++;
    if (id == null) {
      rows.add({
        ...data,
        'id': 'notice',
        'org_name': '검증 복지관',
        'published': false,
      });
    } else {
      rows.firstWhere((n) => n['id'] == id).addAll(data);
    }
    return id ?? 'notice';
  }

  @override
  Future<void> publish(String id, bool value) async {
    if (fail) throw StateError('offline');
    rows.firstWhere((n) => n['id'] == id)['published'] = value;
  }
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
    'home separates official source and community and opens correct details',
    (t) async {
      final r = FakeNotices()
        ..rows.add({
          'id': 'notice',
          'title': '공식 검증 공지',
          'body': '검증 기관에서 등록한 내용',
          'org_name': '검증 복지관',
          'region_sido': '서울특별시',
          'region_sigungu': '강남구',
          'published': true,
        });
      backend.posts.add(backend.post());
      await mount(
        t,
        HomeTab(
          activityRepository: FakeActivityRepository(),
          noticeRepository: r,
        ),
      );
      expect(find.text('기관 공지 · 검증 복지관'), findsOneWidget);
      expect(find.text('지역 커뮤니티 · 자유게시판'), findsOneWidget);
      await tap(t, find.text('공식 검증 공지'));
      expect(find.text('검증 기관에서 등록한 내용'), findsOneWidget);
      await tap(t, find.byTooltip('뒤로'));
      await tap(t, find.text('동네 소식').last);
      expect(find.text('안녕하세요.'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'institution writes draft then explicitly publishes or stops publication',
    (t) async {
      final r = FakeNotices();
      await mount(
        t,
        NoticeManagePage(
          organizations: const [
            {'id': 'org', 'name': '검증 복지관'},
          ],
          repository: r,
        ),
      );
      await tap(t, find.text('공지 작성'));
      await fill(t, '제목', '우리 동네 검증 공지');
      await fill(t, '공지 내용', '기관에서 등록한 안내입니다.');
      await tap(t, find.text('비공개 저장하기'));
      expect(find.text('공지를 저장했어요'), findsOneWidget);
      expect(r.rows.single['published'], false);
      expect(r.rows.single['region_sigungu'], '강남구');
      await tap(t, find.text('확인'));
      expect(find.text('비공개'), findsOneWidget);
      await tap(t, find.text('게시하기'));
      await tap(t, find.text('취소'));
      expect(r.rows.single['published'], false);
      await tap(t, find.text('게시하기'));
      await tap(t, find.text('게시하기').last);
      expect(find.text('게시 중'), findsOneWidget);
      expect(r.rows.single['published'], true);
      await tap(t, find.text('게시 중지'));
      await tap(t, find.text('게시 중지').last);
      expect(r.rows.single['published'], false);
      expect(r.rows.length, 1);
      await finish(t);
    },
  );
  testWidgets(
    'failed save retains entered content and prevents insecure source URLs',
    (t) async {
      final r = FakeNotices()..fail = true;
      await mount(
        t,
        NoticeForm(
          organizations: const [
            {'id': 'org', 'name': '검증 복지관'},
          ],
          repository: r,
        ),
      );
      await fill(t, '제목', '다시 저장할 제목');
      await fill(t, '공지 내용', '유지되어야 하는 본문');
      await fill(t, '원문 링크 (선택)', 'javascript:alert(1)');
      await tap(t, find.text('비공개 저장하기'));
      expect(find.text('https://로 시작하는 원문 주소를 입력해주세요.'), findsOneWidget);
      expect(r.saves, 0);
      await fill(t, '원문 링크 (선택)', 'https://example.org/notice');
      await tap(t, find.text('비공개 저장하기'));
      expect(find.text('저장하지 못했어요'), findsOneWidget);
      await tap(t, find.text('확인'));
      expect(find.text('다시 저장할 제목'), findsOneWidget);
      expect(find.text('유지되어야 하는 본문'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets('official source failure does not hide community and can retry', (
    t,
  ) async {
    final r = FakeNotices()..fail = true;
    backend.posts.add(backend.post());
    await mount(
      t,
      HomeTab(
        activityRepository: FakeActivityRepository(),
        noticeRepository: r,
      ),
    );
    expect(find.text('기관 공지를 불러오지 못했어요.'), findsOneWidget);
    expect(find.text('지역 커뮤니티 · 자유게시판'), findsOneWidget);
    r.fail = false;
    await tap(t, find.text('다시 시도'));
    expect(find.text('아직 등록된 기관 공지가 없어요'), findsOneWidget);
    await finish(t);
  });
}

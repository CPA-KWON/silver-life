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
  bool fail = false, failPreference = false;
  int saves = 0;
  @override
  Future<NoticeData?> preferredInstitution() async {
    if (failPreference) throw StateError('offline');
    return null;
  }

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
    'home shows my institution card beside community and opens community',
    (t) async {
      final r = FakeNotices();
      backend.posts.add(backend.post());
      await mount(
        t,
        HomeTab(
          activityRepository: FakeActivityRepository(),
          noticeRepository: r,
        ),
      );
      expect(find.text('내 복지관 지정하기'), findsOneWidget);
      expect(find.text('지역 커뮤니티 · 자유게시판'), findsOneWidget);
      expect(find.text('기관 공지'), findsNothing);
      await tap(t, find.text('동네 소식').last);
      expect(find.text('안녕하세요.'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets('notice written by the institution shows body and phone', (
    t,
  ) async {
    final r = FakeNotices()
      ..rows.add({
        'id': 'notice',
        'title': '공식 검증 공지',
        'body': '검증 기관에서 등록한 내용',
        'org_name': '검증 복지관',
        'telephone': '02-000-0000',
        'published_at': '2026-10-21T01:00:00Z',
        'region_sido': '서울특별시',
        'region_sigungu': '강남구',
        'published': true,
      });
    await mount(t, NoticeDetailPage(id: 'notice', repository: r));
    expect(find.text('기관 직접 등록'), findsOneWidget);
    expect(find.text('검증 기관에서 등록한 내용'), findsOneWidget);
    expect(find.text('담당자가 앱에서 직접 올렸어요'), findsOneWidget);
    expect(find.text('2026년 10월 21일'), findsOneWidget);
    expect(find.text('문의 02-000-0000'), findsOneWidget);
    expect(find.text('기관에 전화 문의'), findsOneWidget);
    expect(find.text('홈페이지 원문'), findsNothing);
    await finish(t);
  });
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
  testWidgets('my institution failure does not hide community and can retry', (
    t,
  ) async {
    final r = FakeNotices()..failPreference = true;
    backend.posts.add(backend.post());
    await mount(
      t,
      HomeTab(
        activityRepository: FakeActivityRepository(),
        noticeRepository: r,
      ),
    );
    expect(find.text('저장한 복지관을 확인하지 못했어요'), findsOneWidget);
    expect(find.text('지역 커뮤니티 · 자유게시판'), findsOneWidget);
    r.failPreference = false;
    await tap(t, find.text('다시 불러오기'));
    expect(find.text('내 복지관 지정하기'), findsOneWidget);
    await finish(t);
  });
}

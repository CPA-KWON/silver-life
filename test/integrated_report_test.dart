import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/community/post_detail_page.dart';

import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
    backend.posts.add(backend.post()..['author_id'] = 'other-user');
    backend.comments.add({
      'id': 'other-comment',
      'post_id': 'post',
      'author_id': 'other-user',
      'content': '다른 회원의 댓글',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'profiles': {'nickname': '이웃'},
    });
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'merged inline post retains report, cancel and duplicate handling',
    (t) async {
      var closed = false;
      await mount(
        t,
        PostDetailPage(postId: 'post', onClose: () => closed = true),
      );
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      await tap(t, find.text('신고하기'));
      await tap(t, find.text('취소'));
      expect(backend.reports, isEmpty);
      await tap(t, find.text('신고하기'));
      await tap(t, find.text('광고'));
      expect(find.text('신고가 접수됐어요'), findsOneWidget);
      expect(backend.reports.single['post_id'], 'post');
      expect(backend.reports.single['comment_id'], isNull);
      await tap(t, find.text('확인'));
      await tap(t, find.text('신고하기'));
      await tap(t, find.text('광고'));
      expect(find.text('이미 신고하셨어요'), findsOneWidget);
      expect(backend.reports, hasLength(1));
      await tap(t, find.text('확인'));
      await tap(t, find.byType(BackButton));
      expect(closed, isTrue);
      await finish(t);
    },
  );

  testWidgets('merged comment report targets comment independently of post', (
    t,
  ) async {
    await mount(t, const PostDetailPage(postId: 'post'));
    await tap(t, find.text('신고'));
    await tap(t, find.text('욕설·비방'));
    expect(backend.reports.single['comment_id'], 'other-comment');
    expect(backend.reports.single['post_id'], isNull);
    expect(find.text('신고가 접수됐어요'), findsOneWidget);
    await tap(t, find.text('확인'));
    await finish(t);
  });
}

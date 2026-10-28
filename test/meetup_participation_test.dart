import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/community/post_detail_page.dart';
import 'package:silver_life/meetup/my_meetups_page.dart';

import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  Map<String, dynamic> othersMeetup({bool past = false}) =>
      backend.post(id: 'meetup', meetup: true)
        ..['author_id'] = 'someone-else'
        ..['event_at'] = DateTime.now()
            .add(Duration(days: past ? -1 : 2))
            .toUtc()
            .toIso8601String();

  testWidgets('join shows my nickname, then leave asks and reverts', (t) async {
    backend.posts.add(othersMeetup());
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await visible(t, find.text('1/10명'));
    expect(find.text('1/10명'), findsOneWidget);
    expect(find.text('모임장 (모임장)'), findsOneWidget);

    await tap(t, find.text('참여하기'));
    await tap(t, find.widgetWithText(FilledButton, '참여하기'));
    expect(backend.meetupJoined, {'meetup'});
    await visible(t, find.text('2/10명'));
    expect(find.text('2/10명'), findsOneWidget);
    expect(find.text('한결 (나)'), findsOneWidget);
    expect(find.text('참여하기'), findsNothing);

    await tap(t, find.widgetWithText(FilledButton, '참여 취소'));
    await tap(t, find.text('취소'));
    expect(backend.meetupJoined, {'meetup'});
    await tap(t, find.widgetWithText(FilledButton, '참여 취소'));
    await tap(t, find.widgetWithText(FilledButton, '참여 취소하기'));
    expect(backend.meetupJoined, isEmpty);
    expect(find.text('참여하기'), findsOneWidget);
    await finish(t);
  });

  testWidgets('full meetup shows a disabled 모집 마감 button', (t) async {
    backend.posts.add(othersMeetup());
    backend.meetupOthers = 9;
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await visible(t, find.text('10/10명'));
    expect(find.text('10/10명'), findsOneWidget);
    final button = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, '모집 마감'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('참여하기'), findsNothing);
    await finish(t);
  });

  testWidgets('past meetup cannot be joined', (t) async {
    backend.posts.add(othersMeetup(past: true));
    await mount(t, const PostDetailPage(postId: 'meetup'));
    final button = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, '지난 모임'),
    );
    expect(button.onPressed, isNull);
    await finish(t);
  });

  testWidgets('host is listed automatically and has no leave button', (
    t,
  ) async {
    backend.posts.add(backend.post(id: 'meetup', meetup: true));
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await visible(t, find.text('한결 (모임장)'));
    expect(find.text('한결 (모임장)'), findsOneWidget);
    await visible(t, find.text('모임장은 자동으로 참여해요.'));
    expect(find.text('모임장은 자동으로 참여해요.'), findsOneWidget);
    expect(find.text('참여하기'), findsNothing);
    expect(find.text('참여 취소'), findsNothing);
    await finish(t);
  });

  testWidgets('my meetups lists joined meetups split by date', (t) async {
    backend.posts
      ..add(othersMeetup())
      ..add(backend.post(id: 'hosted', meetup: true));
    backend.meetupJoined.add('meetup');
    await mount(t, const MyMeetupsPage());
    expect(find.text('다가오는 모임'), findsOneWidget);
    expect(find.text('복지관 산책 모임'), findsNWidgets(2));
    expect(find.text('모임장'), findsOneWidget);
    await finish(t);
  });
}

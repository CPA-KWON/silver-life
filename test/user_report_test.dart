import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/community/post_detail_page.dart';
import 'package:silver_life/meetup/meetup_flowers.dart';

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

  const button = '사용자 신고하기';

  void addPastMeetup() {
    backend.posts.add(
      backend.post(id: 'meetup', meetup: true)
        ..['author_id'] = 'someone-else'
        ..['event_at'] = DateTime.now()
            .subtract(const Duration(days: 1))
            .toUtc()
            .toIso8601String(),
    );
    backend.meetupJoined.add('meetup');
    backend.meetupOthers = 1;
  }

  Future<void> openCard(WidgetTester t) async {
    await mount(
      t,
      const SingleChildScrollView(child: MeetupFlowersCard(postId: 'meetup')),
    );
  }

  testWidgets('participants can be reported, but not myself', (t) async {
    addPastMeetup();
    await openCard(t);
    // 모임장, 이웃0, 나 중에서 나를 뺀 2명.
    expect(find.text('한결 (나)'), findsOneWidget);
    expect(find.text(button), findsNWidgets(2));
    await finish(t);
  });

  testWidgets('report needs a reason, records it, and refuses a repeat', (
    t,
  ) async {
    addPastMeetup();
    await openCard(t);
    await tap(t, find.text(button).first);
    expect(find.text('신고 이유를 골라 주세요'), findsOneWidget);
    await tap(t, find.text('신고하기'));
    expect(backend.userReports, isEmpty);

    await tap(t, find.text('광고'));
    await tap(t, find.text('신고하기'));
    expect(backend.userReports, ['모임장|광고']);
    expect(find.text('신고가 접수됐어요'), findsOneWidget);
    await tap(t, find.text('확인'));

    await tap(t, find.text(button).first);
    await tap(t, find.text('기타'));
    await tap(t, find.text('신고하기'));
    expect(backend.userReports, hasLength(1));
    expect(find.text('이미 신고하셨어요'), findsOneWidget);
    expect(find.text('같은 사용자는 한 번만 신고할 수 있어요.'), findsOneWidget);
    await finish(t);
  });

  testWidgets('upcoming meetup list also offers the report', (t) async {
    backend.posts.add(
      backend.post(id: 'meetup', meetup: true)..['author_id'] = 'someone-else',
    );
    backend.meetupJoined.add('meetup');
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await t.scrollUntilVisible(
      find.text(button),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    // 모임장과 나 중에서 모임장만.
    expect(find.text(button), findsOneWidget);
    await finish(t);
  });
}

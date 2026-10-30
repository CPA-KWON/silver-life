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

  void addMeetup({bool past = true, bool cancelled = false}) {
    backend.posts.add(
      backend.post(id: 'meetup', meetup: true)
        ..['author_id'] = 'someone-else'
        ..['meetup_cancelled'] = cancelled
        ..['event_at'] = DateTime.now()
            .add(Duration(days: past ? -1 : 2))
            .toUtc()
            .toIso8601String(),
    );
    backend.meetupJoined.add('meetup');
  }

  const send = '꽃 보내기 (1P)';

  // 모임 상세에서 참여자 카드는 화면 아래쪽에 있어 스크롤해야 만들어진다.
  Future<void> openDetail(WidgetTester t) async {
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await t.scrollUntilVisible(
      find.byType(MeetupFlowersCard),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
  }

  testWidgets('finished meetup: button for others only, confirm, then sent', (
    t,
  ) async {
    addMeetup();
    backend.meetupOthers = 1;
    await openDetail(t);
    // 모임장과 이웃 1명에게만 버튼이 있고 나에게는 없다.
    expect(find.text(send), findsNWidgets(2));
    expect(find.text('한결 (나)'), findsOneWidget);
    expect(find.text('받은 꽃 0송이'), findsNWidgets(3));

    await tap(t, find.text(send).last);
    expect(find.textContaining('1P가 차감돼요'), findsOneWidget);
    await tap(t, find.text('취소'));
    expect(backend.flowersSent, isEmpty);
    expect(backend.flowerBalance, 3);

    await tap(t, find.text(send).last);
    await tap(t, find.text('보내기'));
    expect(backend.flowersSent, hasLength(1));
    expect(backend.flowerBalance, 2);
    expect(find.text('보냈어요'), findsOneWidget);
    expect(find.text(send), findsOneWidget);
    expect(find.text('받은 꽃 1송이'), findsOneWidget);
    await finish(t);
  });

  testWidgets('not enough points shows the server message', (t) async {
    addMeetup();
    backend.flowerBalance = 0;
    await openDetail(t);
    await tap(t, find.text(send).last);
    await tap(t, find.text('보내기'));
    expect(find.text('포인트가 부족해요'), findsOneWidget);
    expect(backend.flowersSent, isEmpty);
    expect(find.text('보냈어요'), findsNothing);
    await finish(t);
  });

  testWidgets('upcoming and cancelled meetups have no flower button', (
    t,
  ) async {
    addMeetup(past: false);
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await t.scrollUntilVisible(
      find.text('참여하는 이웃'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    expect(find.byType(MeetupFlowersCard), findsNothing);
    expect(find.text(send), findsNothing);
    await finish(t);

    backend.posts.clear();
    addMeetup(cancelled: true);
    await mount(t, const PostDetailPage(postId: 'meetup'));
    await t.scrollUntilVisible(
      find.text('참여하는 이웃'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    await t.pumpAndSettle();
    expect(find.byType(MeetupFlowersCard), findsNothing);
    expect(find.text(send), findsNothing);
    await finish(t);
  });

  testWidgets('non-participant sees flower counts but no button', (t) async {
    addMeetup();
    backend.meetupJoined.clear();
    await openDetail(t);
    expect(find.text('받은 꽃 0송이'), findsOneWidget);
    expect(find.text(send), findsNothing);
    await finish(t);
  });

  testWidgets('received flowers page lists sender, meetup and date', (t) async {
    backend.myFlowers.add({
      'sender_nickname': '이웃',
      'meetup_title': '복지관 산책 모임',
      'event_at': '2026-10-20T01:00:00Z',
      'created_at': '2026-10-21T01:00:00Z',
    });
    await mount(t, const MyFlowersPage());
    expect(find.text('받은 꽃 1송이'), findsOneWidget);
    expect(find.text('이웃님이 보낸 꽃'), findsOneWidget);
    expect(find.text('복지관 산책 모임'), findsOneWidget);
    expect(find.text('2026년 10월 20일'), findsOneWidget);
    await finish(t);
  });

  testWidgets('received flowers page has a friendly empty state', (t) async {
    await mount(t, const MyFlowersPage());
    expect(find.textContaining('아직 받은 꽃이 없어요'), findsOneWidget);
    await finish(t);
  });

  testWidgets('flower row fits a narrow phone at large text', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    addMeetup();
    await mount(
      t,
      const SingleChildScrollView(child: MeetupFlowersCard(postId: 'meetup')),
      scale: 1.5,
    );
    expect(find.text(send), findsOneWidget);
    expect(t.takeException(), isNull);
    await finish(t);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/social/friends_page.dart';
import 'package:silver_life/social/friends_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/widget_actions.dart';

/// Supabase 없이 화면 동작만 확인하는 가짜 저장소.
class FakeFriendsRepository extends FriendsRepository {
  FakeFriendsRepository({DateTime? checkedInAt})
    : here = [
        {
          'friend_id': 'f1',
          'nickname': '한울',
          'facility_id': 'fac1',
          'facility_name': '강남 경로당',
          'facility_address': '서울 강남구',
          'checked_in_at': (checkedInAt ?? DateTime(2026, 10, 30, 12, 40))
              .toUtc()
              .toIso8601String(),
        },
      ];
  final List<FriendData> here;
  final people = <FriendData>[
    {
      'friendship_id': 'in1',
      'nickname': '새벽',
      'region_sido': '서울특별시',
      'region_sigungu': '서초구',
      'relation': 'incoming',
    },
    {
      'friendship_id': 'fr1',
      'nickname': '한울',
      'region_sido': '서울특별시',
      'region_sigungu': '강남구',
      'relation': 'friend',
    },
    {
      'friendship_id': 'out1',
      'nickname': '보름',
      'region_sido': '부산광역시',
      'region_sigungu': '해운대구',
      'relation': 'outgoing',
    },
  ];
  bool share = true;
  Object? failNextRequest;
  Object? failList;
  final calls = <String>[];

  @override
  Future<List<FriendData>> list() async {
    if (failList != null) throw failList!;
    return [
      for (final p in people) {...p},
    ];
  }

  @override
  Future<List<FriendData>> presence() async => [
    for (final p in here) {...p},
  ];

  @override
  Future<bool> shareEnabled() async => share;

  bool asked = true;
  @override
  Future<bool> shareAsked() async => asked;

  @override
  Future<String> request(String nickname) async {
    calls.add('request:$nickname');
    final error = failNextRequest;
    failNextRequest = null;
    if (error != null) throw error;
    people.add({
      'friendship_id': 'out-$nickname',
      'nickname': nickname,
      'relation': 'outgoing',
    });
    return 'requested';
  }

  @override
  Future<void> respond(String requestId, bool accept) async {
    calls.add('respond:$requestId:$accept');
    final i = people.indexWhere((p) => p['friendship_id'] == requestId);
    if (accept) {
      people[i]['relation'] = 'friend';
    } else {
      people.removeAt(i);
    }
  }

  @override
  Future<void> remove(String friendshipId) async {
    calls.add('remove:$friendshipId');
    people.removeWhere((p) => p['friendship_id'] == friendshipId);
  }

  @override
  Future<void> setShare(bool value) async {
    calls.add('share:$value');
    share = value;
    asked = true;
  }
}

void main() {
  final now = DateTime(2026, 10, 30, 13, 0);
  Future<FakeFriendsRepository> open(
    WidgetTester t, {
    bool asked = true,
    bool share = true,
  }) async {
    // 목록은 보이는 부분만 그려서, 세로로 긴 화면을 써야 맨 아래 항목도 찾을 수 있다.
    t.view.physicalSize = const Size(900, 5000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final repo = FakeFriendsRepository()
      ..asked = asked
      ..share = share;
    await mount(t, FriendsPage(repository: repo, now: () => now));
    return repo;
  }

  testWidgets(
    'shows where friends are now, requests, friends and sent requests',
    (t) async {
      await open(t);
      expect(find.text('친구는 지금 어디에?'), findsOneWidget);
      expect(find.text('한울 님'), findsOneWidget);
      expect(find.text('강남 경로당'), findsOneWidget);
      expect(find.text('20분 전 체크인'), findsOneWidget);
      expect(find.text('받은 친구 요청'), findsOneWidget);
      expect(find.text('새벽'), findsOneWidget);
      expect(find.text('내 친구'), findsOneWidget);
      expect(find.text('보낸 친구 요청'), findsOneWidget);
      expect(find.text('보름'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('first friend asks once whether to show check-ins', (t) async {
    final repo = await open(t, asked: false, share: false);
    expect(find.text('체크인 장소를 친구에게 보여줄까요?'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('share:')), isEmpty);
    await tap(t, find.text('보여 주기'));
    expect(repo.calls, contains('share:true'));
    expect(repo.share, isTrue);
    expect(find.text('체크인 장소를 친구에게 보여줄까요?'), findsNothing);
    expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
  });
  testWidgets('saying no keeps check-ins hidden and is remembered', (t) async {
    final repo = await open(t, asked: false, share: false);
    await tap(t, find.text('보여 주지 않기'));
    expect(repo.calls, contains('share:false'));
    expect(repo.asked, isTrue);
    expect(
      t.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });
  testWidgets('someone already asked is not asked again', (t) async {
    await open(t, asked: true, share: false);
    expect(find.text('체크인 장소를 친구에게 보여줄까요?'), findsNothing);
  });
  testWidgets('people in the friends page can be reported', (t) async {
    await open(t);
    expect(find.text('사용자 신고하기'), findsWidgets);
  });
  testWidgets('accepting a request moves it into my friends', (t) async {
    final repo = await open(t);
    await tap(t, find.text('수락'));
    expect(repo.calls, ['respond:in1:true']);
    expect(find.text('받은 친구 요청'), findsNothing);
    expect(find.text('새벽'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('declining removes the request', (t) async {
    final repo = await open(t);
    await tap(t, find.text('거절'));
    expect(repo.calls, ['respond:in1:false']);
    expect(find.text('새벽'), findsNothing);
  });

  testWidgets('sending a request by nickname shows it under sent requests', (
    t,
  ) async {
    final repo = await open(t);
    await fill(t, '친구 닉네임', '다온');
    await tap(t, find.text('친구 요청 보내기'));
    expect(repo.calls, ['request:다온']);
    expect(find.text('다온'), findsOneWidget);
  });

  testWidgets('empty nickname does not call the server', (t) async {
    final repo = await open(t);
    await tap(t, find.text('친구 요청 보내기'));
    expect(repo.calls, isEmpty);
    expect(find.text('친구의 닉네임을 입력해 주세요'), findsOneWidget);
  });

  testWidgets('server message is shown in easy Korean when a request fails', (
    t,
  ) async {
    final repo = await open(t);
    repo.failNextRequest = PostgrestException(
      message: '해당 닉네임의 이웃을 찾을 수 없어요',
      code: 'P0001',
    );
    await fill(t, '친구 닉네임', '없는사람');
    await tap(t, find.text('친구 요청 보내기'));
    expect(find.text('친구 요청을 보내지 못했어요'), findsOneWidget);
    expect(find.text('해당 닉네임의 이웃을 찾을 수 없어요'), findsOneWidget);
  });

  testWidgets('network errors never show raw technical text', (t) async {
    final repo = await open(t);
    repo.failNextRequest = Exception('SocketException: boom');
    await fill(t, '친구 닉네임', '다온');
    await tap(t, find.text('친구 요청 보내기'));
    expect(find.textContaining('SocketException'), findsNothing);
    expect(find.text('인터넷 연결을 확인한 뒤 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('unfriending asks first, then removes the friend', (t) async {
    final repo = await open(t);
    await tap(t, find.text('친구 끊기'));
    expect(find.text('한울 님과 친구를 끊을까요?'), findsOneWidget);
    expect(repo.calls, isEmpty);
    await tap(t, find.widgetWithText(FilledButton, '친구 끊기'));
    expect(repo.calls, ['remove:fr1']);
  });

  testWidgets('canceling the dialog keeps the friend', (t) async {
    final repo = await open(t);
    await tap(t, find.text('친구 끊기'));
    await tap(t, find.text('취소'));
    expect(repo.calls, isEmpty);
    expect(find.text('한울'), findsWidgets);
  });

  testWidgets('sharing switch is on by default and can be turned off', (
    t,
  ) async {
    final repo = await open(t);
    final tile = find.byType(SwitchListTile);
    await visible(t, tile);
    expect(t.widget<SwitchListTile>(tile).value, isTrue);
    await tap(t, tile);
    expect(repo.calls, ['share:false']);
    expect(t.widget<SwitchListTile>(tile).value, isFalse);
  });

  testWidgets('a clear message appears while friends.sql is not applied yet', (
    t,
  ) async {
    final repo = FakeFriendsRepository()
      ..failList = PostgrestException(
        message: 'Could not find the function',
        code: 'PGRST202',
      );
    await mount(t, FriendsPage(repository: repo, now: () => now));
    expect(find.text('친구 기능을 준비 중이에요'), findsOneWidget);
  });

  testWidgets('works with large text', (t) async {
    final repo = FakeFriendsRepository();
    await mount(t, FriendsPage(repository: repo, now: () => now), scale: 1.6);
    expect(t.takeException(), isNull);
  });
}

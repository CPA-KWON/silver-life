import 'package:supabase_flutter/supabase_flutter.dart';

typedef FriendData = Map<String, dynamic>;

/// 친구 요청·목록·"친구는 지금 어디에?"·내 체크인 공개 설정.
///
/// 표(friendships 등)를 직접 읽거나 쓰지 않고, `supabase/friends.sql`의
/// 서버 함수만 부릅니다. 그래서 친구가 아닌 사람의 체크인은 어떤 경우에도
/// 앱으로 내려오지 않습니다.
class FriendsRepository {
  FriendsRepository({SupabaseClient? client}) : _injectedClient = client;
  final SupabaseClient? _injectedClient;
  // 테스트에서 가짜 저장소를 쓸 때 Supabase 초기화 없이도 만들 수 있게 늦게 가져옵니다.
  SupabaseClient get client => _injectedClient ?? Supabase.instance.client;

  List<FriendData> _rows(dynamic data) => [
    for (final row in data as List) Map<String, dynamic>.from(row as Map),
  ];

  /// 내 친구와 요청 목록. `relation`: friend(친구) / incoming(받은 요청) / outgoing(보낸 요청)
  Future<List<FriendData>> list() async =>
      _rows(await client.rpc('friend_list'));

  /// 지금(최근 3시간) 시설에 체크인한 수락된 친구들. 상대가 공개를 끈 사람은 빠집니다.
  Future<List<FriendData>> presence() async =>
      _rows(await client.rpc('friends_presence'));

  /// 닉네임으로 친구 요청. 'requested'(요청 보냄) 또는 'accepted'(바로 친구가 됨)
  Future<String> request(String nickname) async =>
      '${await client.rpc('friend_request', params: {'target_nickname': nickname})}';

  Future<void> respond(String requestId, bool accept) async {
    await client.rpc(
      'friend_respond',
      params: {'p_request': requestId, 'p_accept': accept},
    );
  }

  /// 친구 끊기 또는 보낸 요청 취소
  Future<void> remove(String friendshipId) async {
    await client.rpc('friend_remove', params: {'p_friendship': friendshipId});
  }

  /// 내 체크인을 친구에게 보여줄지(기본: 안 보임)
  Future<bool> shareEnabled() async =>
      (await client.rpc('friend_share_get')) == true;

  /// 처음 친구를 맺을 때 공개 여부를 이미 물어봤는지
  Future<bool> shareAsked() async =>
      (await client.rpc('friend_share_asked')) == true;

  Future<void> setShare(bool value) async {
    await client.rpc('friend_share_set', params: {'p_share': value});
  }
}

/// 서버가 직접 보낸 쉬운 한국어 안내(예: "이미 친구예요")는 그대로 보여주고,
/// 그 밖의 오류는 쉬운 문구로 바꿉니다.
String friendsErrorMessage(Object error) {
  if (error is PostgrestException &&
      error.code == 'P0001' &&
      error.message.trim().isNotEmpty) {
    return error.message;
  }
  return '인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
}

/// friends.sql 을 아직 Supabase 에서 실행하지 않은 상태
bool friendsNotReady(Object error) =>
    error is PostgrestException &&
    const ['PGRST202', '42883', '42P01'].contains(error.code);

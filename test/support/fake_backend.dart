import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/core/meetup_category.dart';

class FakeBackend {
  static const user = '00000000-0000-0000-0000-000000000001';
  bool failProfile = false, failFavorites = false, failPosts = false;
  bool failAccountDelete = false;
  bool termsAccepted = true;
  final userReports = <String>[];
  Map? signupData;
  // 동네모임 참여: 테스트 사용자가 참여한(모임장이 아닌) 모임 id와,
  // 모임마다 이미 참여한 다른 사람 수.
  final meetupJoined = <String>{};
  int meetupOthers = 0;
  int meetupMax = 10;
  // 고마워요 꽃: 내 포인트, 내가 보낸 '모임|받는사람', 받은 꽃 목록.
  int flowerBalance = 3;
  final flowersSent = <String>{};
  final myFlowers = <Map<String, dynamic>>[];
  int accountDeletes = 0;
  int postWrites = 0, commentWrites = 0, favoriteWrites = 0, checkinWrites = 0;
  final requests = <Uri>[];
  final profile = <String, dynamic>{
    'id': user,
    'nickname': '한결',
    'name': '테스트 이용자',
    'created_at': '2026-01-01T00:00:00Z',
    'region_sido': '서울특별시',
    'region_sigungu': '강남구',
    'birth_year': 1961,
  };
  final facilities = <Map<String, dynamic>>[
    {
      'id': 'facility',
      'name': '테스트 복지관',
      'address': '서울특별시 강남구',
      'category': '복지관',
      'telephone': '02-123-4567',
      'lat': 37.5,
      'lng': 127.0,
      'region_sido': '서울특별시',
      'region_sigungu': '강남구',
    },
  ];
  final posts = <Map<String, dynamic>>[],
      comments = <Map<String, dynamic>>[],
      favorites = <Map<String, dynamic>>[],
      checkins = <Map<String, dynamic>>[],
      reports = <Map<String, dynamic>>[],
          // 내 복지관: 지정 기록, 홈페이지 수집 공지, 기관 직접 등록 공지.
          myNoticeInstitutions =
          <Map<String, dynamic>>[],
      publicNotices = <Map<String, dynamic>>[],
      partnerNotices = <Map<String, dynamic>>[];
  Map<String, dynamic> post({String id = 'post', bool meetup = false}) => {
    'id': id,
    'title': meetup ? '복지관 산책 모임' : '동네 소식',
    'content': '안녕하세요.',
    'author_id': user,
    'category': meetup ? kMeetupCategory : '자유게시판',
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'event_at': DateTime.now()
        .add(const Duration(days: 2))
        .toUtc()
        .toIso8601String(),
    'facility_id': 'facility',
    'facilities': facilities.first,
    'profiles': profile,
    'comments': [
      {'count': 0},
    ],
  };
  Map<String, dynamic> get session {
    final exp =
        DateTime.now().add(const Duration(days: 10)).millisecondsSinceEpoch ~/
        1000;
    String b(Object o) =>
        base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    return {
      'access_token':
          '${b({'alg': 'HS256', 'typ': 'JWT'})}.${b({'sub': user, 'exp': exp, 'role': 'authenticated'})}.test',
      'refresh_token': 'test-only',
      'token_type': 'bearer',
      'expires_in': 864000,
      'expires_at': exp,
      'user': {
        'id': user,
        'aud': 'authenticated',
        'role': 'authenticated',
        'email': 'test@example.invalid',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': {},
        'user_metadata': {},
      },
    };
  }

  Future<void> initialize() async {
    await Supabase.initialize(
      url: 'https://backend.example.invalid',
      publishableKey: 'test-only',
      httpClient: MockClient(handle),
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
        pkceAsyncStorage: TestPkceStorage(),
      ),
    );
    await signIn();
  }

  Future<void> signIn() =>
      Supabase.instance.client.auth.setInitialSession(jsonEncode(session));
  void reset() {
    failProfile = false;
    failFavorites = false;
    failPosts = false;
    posts.clear();
    comments.clear();
    favorites.clear();
    checkins.clear();
    reports.clear();
    myNoticeInstitutions.clear();
    publicNotices.clear();
    partnerNotices.clear();
    requests.clear();
    postWrites = 0;
    commentWrites = 0;
    favoriteWrites = 0;
    checkinWrites = 0;
    profile['nickname'] = '한결';
    failAccountDelete = false;
    termsAccepted = true;
    signupData = null;
    userReports.clear();
    meetupJoined.clear();
    meetupOthers = 0;
    meetupMax = 10;
    flowerBalance = 3;
    flowersSent.clear();
    myFlowers.clear();
    accountDeletes = 0;
  }

  Future<http.Response> handle(http.Request request) async {
    requests.add(request.url);
    final name = request.url.pathSegments.last;
    http.Response response(Object data, {int status = 200}) => http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );
    if (request.url.path.startsWith('/auth/')) {
      if (name == 'logout') return response({});
      final body = request.body.isEmpty ? {} : jsonDecode(request.body) as Map;
      if (name == 'signup') signupData = body['data'] as Map?;
      if (body['password'] == 'wrong-password') {
        return response({
          'msg': 'Invalid login credentials',
          'error_code': 'invalid_credentials',
        }, status: 400);
      }
      return response(session);
    }
    if (name.startsWith('meetup_') ||
        name == 'my_meetups' ||
        name == 'my_flowers' ||
        name == 'send_meetup_flower') {
      final body =
          (request.body.isEmpty ? null : jsonDecode(request.body)) as Map? ??
          {};
      final postId = body['p_post'] as String?;
      final meetup = posts.where((p) => p['id'] == postId).firstOrNull;
      bool isHost(Map p) => p['author_id'] == user;
      bool joinedTo(Map p) => isHost(p) || meetupJoined.contains(p['id']);
      bool isPast(Map p) =>
          !DateTime.parse(p['event_at'] as String).isAfter(DateTime.now());
      int countOf(Map p) =>
          1 + meetupOthers + (!isHost(p) && joinedTo(p) ? 1 : 0);
      http.Response fail(String message) =>
          response({'message': message, 'code': 'P0001'}, status: 400);
      switch (name) {
        case 'my_meetups':
          return response([
            for (final p in posts.where(
              (p) => p['category'] == kMeetupCategory && joinedTo(p),
            ))
              {
                'id': p['id'],
                'title': p['title'],
                'event_at': p['event_at'],
                'facility_name': facilities.first['name'],
                'is_host': isHost(p),
                'count': countOf(p),
                'max_participants': meetupMax,
              },
          ]);
        case 'my_flowers':
          return response(myFlowers);
        case 'send_meetup_flower':
          if (flowerBalance < 1) return fail('포인트가 부족해요');
          flowerBalance--;
          flowersSent.add('$postId|${body['p_to']}');
          return response({'balance': flowerBalance});
        case 'meetup_participation':
          if (meetup == null) return fail('모임을 찾을 수 없어요.');
          Map<String, dynamic> flowerFields(String id, bool me) {
            final sent = flowersSent.contains('$postId|$id');
            final can =
                joinedTo(meetup) &&
                isPast(meetup) &&
                meetup['meetup_cancelled'] != true &&
                !me &&
                !sent;
            return {
              'flowers': sent ? 1 : 0,
              'flower_sent': sent,
              'can_send_flower': can,
              'user_id': can ? id : null,
            };
          }
          return response({
            'max_participants': meetupMax,
            'count': countOf(meetup),
            'joined': joinedTo(meetup),
            'is_host': isHost(meetup),
            'is_past': isPast(meetup),
            'participants': [
              {
                'nickname': isHost(meetup) ? profile['nickname'] : '모임장',
                'is_host': true,
                'is_me': isHost(meetup),
                ...flowerFields('host', isHost(meetup)),
              },
              for (var i = 0; i < meetupOthers; i++)
                {
                  'nickname': '이웃$i',
                  'is_host': false,
                  'is_me': false,
                  ...flowerFields('neighbor$i', false),
                },
              if (!isHost(meetup) && joinedTo(meetup))
                {
                  'nickname': profile['nickname'],
                  'is_host': false,
                  'is_me': true,
                  ...flowerFields(user, true),
                },
            ],
          });
        case 'meetup_join':
          if (meetup == null) return fail('모임을 찾을 수 없어요.');
          if (isPast(meetup)) return fail('이미 지난 모임이에요.');
          if (countOf(meetup) >= meetupMax) return fail('모집이 마감됐어요.');
          meetupJoined.add(postId!);
          return response('');
        case 'meetup_leave':
          if (meetup == null) return fail('모임을 찾을 수 없어요.');
          if (isHost(meetup)) return fail('모임장은 참여를 취소할 수 없어요.');
          meetupJoined.remove(postId);
          return response('');
      }
    }
    if (name == 'terms_accepted') return response(termsAccepted);
    if (name == 'report_user') {
      final body = jsonDecode(request.body) as Map;
      final who = body['p_nickname'];
      if (userReports.any((r) => r.startsWith('$who|'))) {
        return response({'message': 'duplicate', 'code': '23505'}, status: 409);
      }
      userReports.add('$who|${body['p_reason']}');
      return response('');
    }
    if (name == 'accept_terms') {
      termsAccepted = true;
      return response('');
    }
    if (name == 'delete_my_account') {
      if (failAccountDelete) {
        return response({'message': 'failed', 'code': 'P0001'}, status: 400);
      }
      accountDeletes++;
      return response('');
    }
    if (name == 'facility_guide') return response({});
    if (name == 'facility_check_in') {
      final b = jsonDecode(request.body) as Map;
      checkins.removeWhere(
        (r) =>
            r['facility_id'] == b['target_facility'] &&
            r['user_id'] == profile['id'],
      );
      checkins.add({
        'user_id': profile['id'],
        'facility_id': b['target_facility'],
        'checked_in_at': DateTime.now().toUtc().toIso8601String(),
      });
      checkinWrites++;
      return response('');
    }
    if (name == 'facility_presence') {
      final body = jsonDecode(request.body) as Map;
      final active = checkins
          .where(
            (r) =>
                r['facility_id'] == body['target_facility'] &&
                DateTime.parse(r['checked_in_at'] as String)
                    .isAfter(DateTime.now().subtract(const Duration(hours: 3))),
          )
          .toList();
      return response({
        'count': active.length,
        'checked_in': active.any((r) => r['user_id'] == profile['id']),
      });
    }
    if (name == 'ensure_facility') {
      final data = Map<String, dynamic>.from(
        (jsonDecode(request.body) as Map)['data'] as Map,
      );
      final existing = facilities.where(
        (r) => r['name'] == data['name'] && r['address'] == data['address'],
      );
      if (existing.isNotEmpty) return response(existing.first['id']!);
      final id = 'facilities-${facilities.length}';
      facilities.add({'id': id, ...data});
      return response(id);
    }
    if (request.url.path.contains('/storage/v1/object/list/')) {
      return response([]);
    }
    if (name == 'institution_notice_feed') return response([]);
    if (name == 'email_exists') return response(false);
    if ((name == 'profiles' && failProfile) ||
        (name == 'favorites' && failFavorites) ||
        (name == 'posts' && failPosts)) {
      return response({
        'code': 'TEST',
        'message': 'connection failure',
      }, status: 400);
    }
    if (name == 'reports' && request.method == 'POST') {
      final data = jsonDecode(request.body) as Map;
      if (reports.any(
        (r) =>
            r['reporter_id'] == data['reporter_id'] &&
            r['post_id'] == data['post_id'] &&
            r['comment_id'] == data['comment_id'],
      )) {
        return response({'code': '23505', 'message': 'duplicate'}, status: 409);
      }
    }
    final tables = {
      'profiles': [profile],
      'posts': posts,
      'comments': comments,
      'favorites': favorites,
      'facilities': facilities,
      'checkins': checkins,
      'reports': reports,
      'my_notice_institutions': myNoticeInstitutions,
      'public_institution_notices': publicNotices,
      'institution_notices': partnerNotices,
    };
    final table = tables[name];
    if (table == null) {
      return response({
        'code': 'PGRST202',
        'message': 'not prepared',
      }, status: 400);
    }
    bool matches(Map<String, dynamic> row) {
      for (final e in request.url.queryParameters.entries) {
        if ([
              'select',
              'order',
              'limit',
              'offset',
              'on_conflict',
            ].contains(e.key) ||
            e.key.contains('.')) {
          continue;
        }
        final value = row[e.key];
        if (e.value.startsWith('eq.') && '$value' != e.value.substring(3)) {
          return false;
        }
        if (e.value.startsWith('neq.') && '$value' == e.value.substring(4)) {
          return false;
        }
      }
      return true;
    }

    if (request.method == 'POST' || request.method == 'PATCH') {
      final decoded = jsonDecode(request.body);
      final values = decoded is List ? decoded : [decoded];
      for (final raw in values) {
        final data = Map<String, dynamic>.from(raw as Map);
        if (request.method == 'PATCH') {
          for (final row in table.where(matches)) {
            row.addAll(data);
          }
        } else if (name == 'checkins' && table.isNotEmpty) {
          table.first.addAll(data);
        } else if (name == 'facilities' && table.isNotEmpty) {
          table.first.addAll(data);
        } else {
          table.add({
            'id': '$name-${table.length}',
            ...data,
            if (name == 'posts') 'profiles': profile,
            if (name == 'comments') 'profiles': profile,
            'created_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      }
      if (name == 'posts') postWrites++;
      if (name == 'comments') commentWrites++;
      if (name == 'favorites') favoriteWrites++;
      if (name == 'checkins') checkinWrites++;
    } else if (request.method == 'DELETE') {
      table.removeWhere(matches);
      if (name == 'posts') postWrites++;
      if (name == 'favorites') favoriteWrites++;
      if (name == 'checkins') checkinWrites++;
    }
    final rows = table.where(matches).toList();
    if (request.headers['accept']?.contains('vnd.pgrst.object') == true) {
      if (rows.isEmpty) {
        return response({
          'code': 'PGRST116',
          'message': 'not found',
        }, status: 406);
      }
      return response(rows.first);
    }
    return response(rows);
  }
}

class TestPkceStorage extends GotrueAsyncStorage {
  const TestPkceStorage();
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

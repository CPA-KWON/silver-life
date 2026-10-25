import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/core/meetup_category.dart';

class FakeBackend {
  static const user = '00000000-0000-0000-0000-000000000001';
  bool failProfile = false, failFavorites = false, failPosts = false;
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
      reports = <Map<String, dynamic>>[];
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
    requests.clear();
    postWrites = 0;
    commentWrites = 0;
    favoriteWrites = 0;
    checkinWrites = 0;
    profile['nickname'] = '한결';
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
      if (body['password'] == 'wrong-password') {
        return response({
          'msg': 'Invalid login credentials',
          'error_code': 'invalid_credentials',
        }, status: 400);
      }
      return response(session);
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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/activity/activity_repository.dart';

import 'support/fake_backend.dart';

void main() {
  test(
    'real repository sends authenticated RPC arguments and owner-scoped writes',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://transport.example.invalid',
        'test-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((req) async {
          requests.add(req);
          final name = req.url.pathSegments.last;
          final body =
              [
                'activity_home',
                'activity_program_detail',
                'activity_agency',
              ].contains(name)
              ? '{}'
              : 'null';
          return http.Response(
            body,
            200,
            headers: {'content-type': 'application/json'},
            request: req,
          );
        }),
      );
      await client.auth.setInitialSession(jsonEncode(FakeBackend().session));
      final repo = ActivityRepository(client: client);
      await repo.home();
      await repo.detail('program');
      await repo.agency();
      await repo.plan(rebuild: true);
      await repo.preferences({'place_name': '동네'});
      await repo.experience({'title': '재봉'});
      await repo.experience({'active': false}, id: 'experience');
      await repo.apply('program', experienceId: 'experience');
      await repo.cancel('enrollment');
      await repo.manage('enrollment', 'completed');
      await repo.program({'title': '프로그램'});
      await repo.close('program');
      Map<String, dynamic> body(String name) => jsonDecode(
        requests.firstWhere((r) => r.url.pathSegments.last == name).body,
      ) as Map<String, dynamic>;
      expect(body('activity_program_detail'), {'program_id': 'program'});
      expect(body('activity_plan_week'), {'rebuild_unstarted': true});
      expect(body('activity_apply_with_note'), {
        'target_program': 'program',
        'target_experience': 'experience',
        'application_note': '',
      });
      expect(body('activity_cancel'), {'enrollment': 'enrollment'});
      expect(body('activity_manage'), {
        'enrollment': 'enrollment',
        'action': 'completed',
      });
      expect(body('activity_save_program_v3'), {
        'data': {'title': '프로그램'},
      });
      expect(body('activity_close_program'), {'target_program': 'program'});
      expect(body('activity_preferences')['user_id'], FakeBackend.user);
      expect(body('activity_experiences')['user_id'], FakeBackend.user);
      final edit = requests.firstWhere((r) => r.method == 'PATCH');
      expect(edit.url.queryParameters['user_id'], 'eq.${FakeBackend.user}');
      expect(
        requests.every(
          (r) => r.headers['authorization']?.startsWith('Bearer ') == true,
        ),
        true,
      );
      expect(
        requests.any(
          (r) => [
            'profiles',
            'posts',
            'comments',
            'facilities',
            'favorites',
            'checkins',
          ].contains(r.url.pathSegments.last),
        ),
        false,
      );
      await client.dispose();
    },
  );
}

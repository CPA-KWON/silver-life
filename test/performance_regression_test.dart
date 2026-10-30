import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/activity/activity_repository.dart';
import 'package:silver_life/attendance/attendance_controller.dart';
import 'package:silver_life/attendance/attendance_repository.dart';
import 'package:silver_life/home/main_shell.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';
import 'package:silver_life/social/neighborhood_feed.dart';

import 'support/fake_activity_repository.dart';
import 'support/fake_attendance_repository.dart';
import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

class _DelayedAttendance extends FakeAttendanceRepository {
  final pending = Completer<AttendanceStatus>();
  int reads = 0;
  @override
  Future<AttendanceStatus> status() {
    reads++;
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  test('overlapping wallet reads share a request and late status cannot undo a stamp', () async {
    final repository = _DelayedAttendance();
    final controller = AttendanceController(repository: repository);
    final first = controller.refresh();
    final second = controller.refresh();
    expect(identical(first, second), isTrue);
    expect(repository.reads, 1);
    await controller.checkIn();
    expect(controller.status!.balance, 1);
    repository.pending.complete(
      AttendanceStatus(
        today: repository.today,
        attendedToday: false,
        streak: 0,
        balance: 0,
        totalEarned: 0,
      ),
    );
    expect((await first)!.attendedToday, isTrue);
    expect((await second)!.balance, 1);
    expect(controller.status!.balance, 1);
    controller.dispose();
  });

  test(
    'activity supplemental reads start together and keep independent errors',
    () async {
      final gates = {
        for (final name in [
          'activity_benefits',
          'pet_history',
          'welfare_programs',
        ])
          name: Completer<void>(),
      };
      final started = <String>{};
      final allStarted = Completer<void>();
      final client = SupabaseClient(
        'https://parallel.example.invalid',
        'test-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          final name = request.url.pathSegments.last;
          if (gates.containsKey(name)) {
            started.add(name);
            if (started.length == gates.length) allStarted.complete();
            await gates[name]!.future;
          }
          return http.Response(
            name == 'activity_home' ? '{}' : '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      await client.auth.setInitialSession(jsonEncode(backend.session));
      final home = ActivityRepository(client: client).home();
      try {
        await allStarted.future.timeout(const Duration(seconds: 2));
        expect(started, gates.keys.toSet());
      } finally {
        for (final gate in gates.values) {
          if (!gate.isCompleted) gate.complete();
        }
      }
      final data = await home;
      expect(data['benefits'], isEmpty);
      expect(data['mission_rewards'], isEmpty);
      expect(data['welfare_programs'], isEmpty);
      await client.dispose();
    },
  );

  test(
    'home summary never loads catalog or optional reward histories',
    () async {
      final paths = <String>[];
      final client = SupabaseClient(
        'https://summary.example.invalid',
        'test-only',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          paths.add(request.url.pathSegments.last);
          return http.Response(
            '{"applications":[],"organizations":[]}',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final data = await ActivityRepository(client: client).homeSummary();
      expect(data['applications'], isEmpty);
      expect(paths, ['activity_home']);
      await client.dispose();
    },
  );

  testWidgets(
    'social tabs retain filters and scroll, build cards lazily, and avoid repeat fetches',
    (t) async {
      backend.posts.addAll(
        List.generate(
          100,
          (i) => {...backend.post(id: 'post-$i'), 'title': '커뮤니티 글 $i'},
        ),
      );
      final attendance = FakeAttendanceRepository();
      await attendance.checkIn();
      final pet = PetPreviewController();
      await mount(
        t,
        MainShell(
          activityRepository: FakeActivityRepository(),
          attendanceRepository: attendance,
          petController: pet,
          facilityPage: const ColoredBox(color: Colors.blue),
        ),
      );
      final community = find.widgetWithText(NavigationDestination, '커뮤니티');
      final meetup = find.widgetWithText(NavigationDestination, '동네 모임');
      await t.tap(community);
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await t.pumpAndSettle();
      expect(find.text('커뮤니티 글 99'), findsNothing);
      final feed = find.byType(NeighborhoodFeed);
      final originalState = t.state(feed);
      final list = find.byKey(const PageStorageKey('community-feed'));
      await t.drag(list, const Offset(0, -500));
      await t.pumpAndSettle();
      final position = t
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position;
      final offset = position.pixels;
      expect(offset, greaterThan(0));
      await tap(t, meetup);
      final requests = backend.requests.length;
      await tap(t, community);
      expect(
        identical(t.state(find.byType(NeighborhoodFeed)), originalState),
        isTrue,
      );
      expect(position.pixels, offset);
      expect(backend.requests.length, requests);
      expect(t.takeException(), isNull);
      await finish(t);
      pet.dispose();
    },
  );
}

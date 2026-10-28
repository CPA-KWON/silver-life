import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/home/main_shell.dart';
import 'package:silver_life/auth/auth_gate.dart';
import 'package:silver_life/activity/activity_hub_page.dart';
import 'package:silver_life/profile/profile_page.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';
import 'support/widget_actions.dart';

void main() {
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  testWidgets(
    'activity pages keep global navigation and the existing map element',
    (t) async {
      final r = FakeActivityRepository()..pref = {'place_name': '동네'};
      await mount(
        t,
        MainShell(
          activityRepository: r,
          facilityPage: const ColoredBox(
            key: ValueKey('retained-native-map'),
            color: Colors.blue,
          ),
        ),
      );
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.widgetWithText(NavigationDestination, '내 정보'), findsNothing);
      await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
      final original = t.element(
        find.byKey(const ValueKey('retained-native-map')),
      );
      await tap(t, find.widgetWithText(NavigationDestination, '활동'));
      expect(find.byType(TabBar), findsNothing);
      await tap(t, find.text('주간 미션'));
      await tap(t, find.text('프로그램별 주간 미션 보기'));
      expect(find.text('이번 주 미션 만들기'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tap(t, find.widgetWithText(NavigationDestination, '시설 찾기'));
      expect(
        identical(
          original,
          t.element(find.byKey(const ValueKey('retained-native-map'))),
        ),
        true,
      );
      await tap(t, find.widgetWithText(NavigationDestination, '활동'));
      expect(find.text('이번 주 미션 만들기'), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(ActivityHubPage), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'home recommendations open the activity stack with bottom navigation',
    (t) async {
      final r = FakeActivityRepository()..pref = {'place_name': '동네'};
      await mount(t, MainShell(activityRepository: r));
      await tap(t, find.text('맞춤 활동 찾기'));
      expect(find.byType(ActivitySectionPage), findsOneWidget);
      await visible(t, find.text('전체 프로그램 탐색'));
      expect(find.text('전체 프로그램 탐색'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tap(t, find.byTooltip('뒤로'));
      expect(find.byType(ActivityHubPage), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets('back from profile does not pop an inactive activity stack', (
    t,
  ) async {
    final r = FakeActivityRepository()..pref = {'place_name': '동네'};
    await mount(t, AuthGate(signedInPage: MainShell(activityRepository: r)));
    await tap(t, find.widgetWithText(NavigationDestination, '활동'));
    await tap(t, find.text('주간 미션'));
    await tap(t, find.text('프로그램별 주간 미션 보기'));
    await tap(t, find.widgetWithText(NavigationDestination, '홈'));
    await tap(t, find.text('내 정보'));
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('다가오는 모임'), findsOneWidget);
    expect(find.text('이번 주 활동 현황'), findsNothing);
    await tap(t, find.widgetWithText(NavigationDestination, '활동'));
    expect(find.text('이번 주 미션 만들기'), findsOneWidget);
    await finish(t);
  });
  testWidgets(
    'Android back across session and activity navigators never pops the signed-in root',
    (t) async {
      final r = FakeActivityRepository();
      await mount(t, AuthGate(signedInPage: MainShell(activityRepository: r)));
      await tap(t, find.widgetWithText(NavigationDestination, '활동'));
      await tap(t, find.text('맞춤 활동 찾기'));
      await tap(t, find.text('전체 프로그램 탐색'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text('전체 프로그램 탐색'), findsOneWidget);
      expect(find.byType(MainShell), findsOneWidget);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      await visible(t, find.text('경험 나눔'));
      expect(find.text('경험 나눔'), findsOneWidget);
      expect(find.byType(MainShell), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'profile logout clears retained activity routes and cancellation keeps session',
    (t) async {
      final r = FakeActivityRepository();
      await mount(t, AuthGate(signedInPage: MainShell(activityRepository: r)));
      await tap(t, find.widgetWithText(NavigationDestination, '활동'));
      await tap(t, find.text('나의 활동'));
      await tap(t, find.widgetWithText(NavigationDestination, '홈'));
      await tap(t, find.text('내 정보'));
      await tap(t, find.text('로그아웃'));
      await tap(t, find.text('취소'));
      expect(Supabase.instance.client.auth.currentUser, isNotNull);
      await tap(t, find.text('로그아웃'));
      await tap(t, find.widgetWithText(TextButton, '로그아웃'));
      expect(Supabase.instance.client.auth.currentUser, isNull);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(ActivitySectionPage), findsNothing);
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byType(ActivitySectionPage), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'experience purposes are separate and support history excludes ordinary applications',
    (t) async {
      final r = FakeActivityRepository()..addSupport();
      await r.apply('program');
      await r.apply('support');
      await mount(
        t,
        ActivitySectionPage(section: ActivitySection.experience, repository: r),
      );
      await tap(t, find.text('지원 현황'));
      expect(find.text('산책 경험 나눔'), findsOneWidget);
      expect(find.text('가벼운 산책'), findsNothing);
      await tap(t, find.byTooltip('뒤로'));
      await tap(t, find.text('내 경험 관리'));
      await tap(t, find.text('나눌 경험 등록'));
      expect(find.textContaining('내 경험은 나만 볼 수 있어요.'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'my activity switches between status history and benefit without sideways pages',
    (t) async {
      final r = FakeActivityRepository()
        ..benefit = true
        ..addSupport();
      await r.apply('program');
      await r.apply('support');
      r.applications.last['status'] = 'completed';
      await mount(
        t,
        ActivitySectionPage(section: ActivitySection.mine, repository: r),
      );
      expect(find.text('가벼운 산책'), findsOneWidget);
      expect(find.text('산책 경험 나눔'), findsNothing);
      await tap(t, find.text('신청 내역'));
      await tap(t, find.text('참여 이력').last);
      expect(find.text('산책 경험 나눔'), findsOneWidget);
      await tap(t, find.text('참여 이력'));
      await tap(t, find.text('혜택').last);
      expect(find.textContaining('50% 혜택'), findsOneWidget);
      expect(find.byType(TabBarView), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'profile hides institutional tools for ordinary users and routes all manager purposes',
    (t) async {
      final r = FakeActivityRepository();
      await mount(t, ProfilePage(activityRepository: r));
      expect(find.text('기관 관리'), findsNothing);
      r.manager = true;
      await mount(t, ProfilePage(activityRepository: r));
      await tap(t, find.text('기관 관리'));
      for (final (entry, label) in [
        ('프로그램', '프로그램 관리'),
        ('신청자', '신청자 관리'),
        ('경험 나눔', '경험 나눔 관리'),
        ('운영 성과', '운영 성과'),
      ]) {
        await tap(t, find.text(entry));
        expect(find.text(label), findsOneWidget);
        expect(t.takeException(), isNull);
        await tap(t, find.byTooltip('뒤로'));
      }
      await tap(t, find.text('경험 나눔'));
      await tap(t, find.text('경험 나눔 모집 관리'));
      await tap(t, find.text('경험 나눔 모집 등록'));
      expect(find.text('경험 나눔 모집 등록'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '참여비 (원)'), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'facility program connection matches both place and coordinates',
    (t) async {
      final r = FakeActivityRepository()..addSupport();
      r.programs.add({
        ...r.programs.first,
        'id': 'other',
        'title': '다른 시설 활동',
        'place_name': '다른 시설',
      });
      await mount(
        t,
        ActivitySectionPage(
          section: ActivitySection.programs,
          repository: r,
          place: (name: '동네 공원', lat: 37.5666, lng: 126.979),
        ),
      );
      expect(find.text('가벼운 산책'), findsOneWidget);
      await visible(t, find.text('산책 경험 나눔'));
      expect(find.text('산책 경험 나눔'), findsOneWidget);
      expect(find.text('다른 시설 활동'), findsNothing);
      await finish(t);
    },
  );
  testWidgets(
    'temporary auth refresh error preserves the session and private home',
    (t) async {
      await mount(
        t,
        AuthGate(
          signedInPage: MainShell(activityRepository: FakeActivityRepository()),
        ),
      );
      // Failure injection into the pinned SDK's auth stream; not used by app code.
      // ignore: invalid_use_of_internal_member
      Supabase.instance.client.auth.notifyException(
        AuthRetryableFetchException(message: 'test network interruption'),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(Supabase.instance.client.auth.currentUser, isNotNull);
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.text('다가오는 모임'), findsOneWidget);
      await finish(t);
    },
  );
}

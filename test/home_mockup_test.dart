import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/home/home_tab.dart';
import 'package:silver_life/pet/pet_preview_controller.dart';

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
  testWidgets('empty home keeps adoption first and omits empty weekly block', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(430, 960));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final pet = PetPreviewController()..ready = true;
    addTearDown(pet.dispose);
    var adopted = false;
    await mount(
      t,
      HomeTab(
        petPreview: pet,
        onOpenPet: () => adopted = true,
        activityRepository: FakeActivityRepository(),
      ),
    );
    expect(find.text('이번 주 활동 현황'), findsNothing);
    expect(find.text('시작 전'), findsNothing);
    expect(
      t.getTopLeft(find.text('반려동물 만나기')).dy,
      lessThan(t.getTopLeft(find.text('다가오는 모임')).dy),
    );
    expect(find.text('동네 소식'), findsOneWidget);
    expect(find.text('아직 우리 동네 글이 없어요'), findsOneWidget);
    await tap(t, find.text('반려동물 만나기'));
    expect(adopted, true);
    await tap(t, find.byKey(const ValueKey('home-community-more')));
    expect(find.text('우리 동네에 아직 글이 없어요'), findsOneWidget);
    await finish(t);
  });
  testWidgets('home lists meetups I joined first, marked 참여 예정', (t) async {
    final later = DateTime.now().add(const Duration(days: 5)).toUtc();
    backend.posts.addAll([
      backend.post(id: 'nearby', meetup: true)
        ..['author_id'] = 'neighbor'
        ..['title'] = '가까운 모임',
      backend.post(id: 'joined', meetup: true)
        ..['author_id'] = 'neighbor'
        ..['title'] = '내가 참여한 모임'
        ..['event_at'] = later.toIso8601String(),
    ]);
    backend.meetupJoined.add('joined');
    await mount(t, HomeTab(activityRepository: FakeActivityRepository()));
    final joinedTop = t.getTopLeft(find.text('내가 참여한 모임')).dy;
    expect(joinedTop, lessThan(t.getTopLeft(find.text('가까운 모임')).dy));
    expect(find.text('참여 예정'), findsOneWidget);
    await finish(t);
  });
  testWidgets(
    'local meetup and news use existing detail routes with honest source labels',
    (t) async {
      backend.posts.addAll([
        backend.post(id: 'meetup', meetup: true)..['author_id'] = 'neighbor',
        backend.post(id: 'news'),
      ]);
      await mount(t, HomeTab(activityRepository: FakeActivityRepository()));
      expect(find.text('복지관 산책 모임'), findsOneWidget);
      expect(find.text('지역 커뮤니티 · 자유게시판'), findsOneWidget);
      // 남의 모임은 참여 전까지 "참여 예정"으로 표시하지 않는다.
      expect(find.text('참여 예정'), findsNothing);
      final calls = backend.requests
          .where((u) => u.path.endsWith('/posts'))
          .toList();
      expect(
        calls.any(
          (u) => u.queryParameters['facilities.region_sigungu'] == 'eq.강남구',
        ),
        true,
      );
      expect(
        calls.any(
          (u) => u.queryParameters['profiles.region_sigungu'] == 'eq.강남구',
        ),
        true,
      );
      await tap(t, find.text('동네 소식').last);
      expect(find.text('안녕하세요.'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'failed local feed has retry and does not look like an empty feed',
    (t) async {
      backend.failPosts = true;
      await mount(t, HomeTab(activityRepository: FakeActivityRepository()));
      expect(find.text('커뮤니티 글을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('아직 우리 동네 글이 없어요'), findsNothing);
      backend.failPosts = false;
      await tap(t, find.text('다시 시도').last);
      expect(find.text('아직 우리 동네 글이 없어요'), findsOneWidget);
      await finish(t);
    },
  );
}

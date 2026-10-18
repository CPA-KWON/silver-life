import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/auth/login_page.dart';
import 'package:silver_life/auth/auth_gate.dart';
import 'package:silver_life/auth/signup_page.dart';
import 'package:silver_life/home/main_shell.dart';
import 'package:silver_life/profile/account_settings_page.dart';
import 'package:silver_life/home/home_tab.dart';
import 'package:silver_life/community/community_page.dart';
import 'package:silver_life/community/post_detail_page.dart';
import 'package:silver_life/meetup/meetup_page.dart';
import 'package:silver_life/meetup/new_meetup_page.dart';
import 'package:silver_life/profile/profile_page.dart';
import 'package:silver_life/facility/facility_search_page.dart';
import 'package:silver_life/core/phone_call.dart';
import 'package:silver_life/core/region_picker.dart';
import 'package:silver_life/core/korea_regions.dart';

import 'support/fake_backend.dart';
import 'support/fake_activity_repository.dart';

import 'package:silver_life/facility/nearby_facilities_page.dart';

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
  testWidgets(
    'home keeps greeting when activities fail and retry restores summary',
    (t) async {
      final repo = FakeActivityRepository()..fail = true;
      await mount(t, HomeTab(activityRepository: repo));
      expect(find.textContaining('안녕하세요'), findsOneWidget);
      expect(find.text('활동 현황을 불러오지 못했어요.'), findsOneWidget);
      repo.fail = false;
      await tap(t, find.text('다시 시도'));
      expect(find.text('이번 주 활동 현황'), findsOneWidget);
      expect(find.text('최근 커뮤니티 글'), findsNothing);
      await finish(t);
    },
  );
  testWidgets('home profile entry and activity shortcut return to summary', (
    t,
  ) async {
    final repo = FakeActivityRepository();
    await mount(t, HomeTab(activityRepository: repo));
    await tap(t, find.text('내 정보'));
    await tap(t, find.text('나의 활동'));
    expect(find.text('아직 신청한 활동이 없어요.'), findsOneWidget);
    await tap(t, find.byType(BackButton));
    await tap(t, find.byType(BackButton));
    expect(find.text('이번 주 활동 현황'), findsOneWidget);
    await finish(t);
  });
  testWidgets('community and meetup region failures have usable retry', (
    t,
  ) async {
    backend.failProfile = true;
    await mount(t, const CommunityPage());
    await tap(t, find.text('다시 시도'));
    backend.failProfile = false;
    await tap(t, find.text('다시 시도'));
    expect(find.text('아직 게시글이 없습니다.'), findsOneWidget);
    backend.failProfile = true;
    await mount(t, const MeetupPage());
    backend.failProfile = false;
    await tap(t, find.text('다시 시도'));
    expect(find.textContaining('모임이 없습니다.'), findsOneWidget);
    await finish(t);
  });
  testWidgets('post edit, comment and delete buttons use existing CRUD', (
    t,
  ) async {
    backend.posts.add(backend.post());
    await mount(t, const PostDetailPage(postId: 'post'));
    await tap(t, find.byType(PopupMenuButton<String>));
    await tap(t, find.text('수정'));
    await fill(t, '제목', '수정한 소식');
    await tap(t, find.text('수정하기'));
    expect(backend.postWrites, 1);
    expect(find.text('수정한 소식'), findsOneWidget);
    final input = find.byType(TextField).last;
    await t.enterText(input, '응원합니다');
    await tap(t, find.byIcon(Icons.send));
    expect(backend.commentWrites, 1);
    await tap(t, find.byType(PopupMenuButton<String>));
    await tap(t, find.text('삭제'));
    await tap(t, find.widgetWithText(TextButton, '삭제'));
    expect(backend.posts, isEmpty);
    await finish(t);
  });
  testWidgets('past meetup opens date dialog without invalid initial date', (
    t,
  ) async {
    final post = backend.post(meetup: true)
      ..['event_at'] = '2025-01-01T01:00:00Z';
    await mount(
      t,
      NewMeetupPage(existingPost: {...post, 'facility': post['facilities']}),
    );
    await tap(t, find.text('날짜'));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tap(t, find.text('취소'));
    expect(t.takeException(), isNull);
    await finish(t);
  });
  testWidgets('home facility page keeps only its outer back arrow', (t) async {
    await mount(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('시설찾기')),
                body: const FacilitySearchPage(
                  initialFacility: testPlace,
                  showDetailBackButton: false,
                  mapPlaceholder: ColoredBox(color: Colors.blue),
                  enableRealtime: false,
                ),
              ),
            ),
          ),
          child: const Text('시설 열기'),
        ),
      ),
    );
    await tap(t, find.text('시설 열기'));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.text('테스트 복지관'), findsWidgets);
    expect(find.byTooltip('즐겨찾기'), findsOneWidget);
    await tap(t, find.byType(BackButton));
    expect(find.byType(FacilityDetailPage), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tap(t, find.byType(BackButton));
    expect(find.text('시설 열기'), findsOneWidget);
    await finish(t);
  });

  testWidgets('map facility favorite and presence buttons work', (t) async {
    await mount(
      t,
      const FacilitySearchPage(
        initialFacility: testPlace,
        mapPlaceholder: ColoredBox(color: Colors.blue),
        enableRealtime: false,
      ),
    );
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await tap(t, find.byTooltip('즐겨찾기'));
    expect(backend.favorites.length, 1);
    await tap(t, find.text('나 여기 있음'));
    expect(backend.checkins.length, 1);
    await tap(t, find.text('나 여기 있음 취소'));
    expect(backend.checkins, isEmpty);
    await tap(t, find.byTooltip('즐겨찾기'));
    expect(backend.favorites, isEmpty);
    await finish(t);
  });
  testWidgets(
    'map post and editor overlays preserve map element and unsaved form',
    (t) async {
      backend.posts.add(backend.post(meetup: true));
      await mount(
        t,
        const FacilitySearchPage(
          initialFacility: testPlace,
          mapPlaceholder: ColoredBox(key: ValueKey('map'), color: Colors.blue),
          enableRealtime: false,
        ),
      );
      final map = t.element(find.byKey(const ValueKey('map')));
      await tap(t, find.text('복지관 산책 모임'));
      await tap(t, find.byType(PopupMenuButton<String>));
      await tap(t, find.text('수정'));
      await fill(t, '모임 제목', '보존할 제목');
      await tap(t, find.text('테스트 복지관').last);
      await tap(t, find.text('장소 선택 취소'));
      expect(find.text('보존할 제목'), findsOneWidget);
      await tap(t, find.byType(BackButton).last);
      expect(
        identical(map, t.element(find.byKey(const ValueKey('map')))),
        true,
      );
      await finish(t);
    },
  );
  testWidgets(
    'profile account settings return refreshes without async setState',
    (t) async {
      await mount(t, ProfilePage(activityRepository: FakeActivityRepository()));
      await tap(t, find.text('회원정보 관리'));
      backend.profile['nickname'] = '변경 닉네임';
      await tap(t, find.byType(BackButton));
      await t.drag(find.byType(ListView).last, const Offset(0, 1500));
      await t.pumpAndSettle();
      expect(find.text('변경 닉네임'), findsOneWidget);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets('phone failure exposes usable number', (t) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    await mount(
      t,
      Builder(
        builder: (c) => TextButton(
          onPressed: () => callFacility(c, '02-123-4567'),
          child: const Text('전화'),
        ),
      ),
    );
    await tap(t, find.text('전화'));
    expect(find.textContaining('02-123-4567'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await finish(t);
  });
  testWidgets('login wrong password reports error and allows retry', (t) async {
    await t.runAsync(() => Supabase.instance.client.auth.signOut());
    await mount(t, const LoginPage());
    await fill(t, '이메일 (아이디)', 'test@example.invalid');
    await fill(t, '비밀번호', 'wrong-password');
    await tap(t, find.widgetWithText(FilledButton, '로그인'));
    expect(Supabase.instance.client.auth.currentUser, isNull);
    await fill(t, '비밀번호', 'right-password');
    await tap(t, find.widgetWithText(FilledButton, '로그인'));
    expect(Supabase.instance.client.auth.currentUser, isNotNull);
    await finish(t);
  });
  testWidgets('signup duplicate check and complete form submit', (t) async {
    await mount(t, const SignupPage());
    for (final e in {
      '이메일 (아이디)': 'new@example.invalid',
      '비밀번호 (6자 이상)': 'password-123',
      '비밀번호 확인': 'password-123',
      '이름': '테스트',
      '닉네임': '새 이웃',
      '출생년도 (예: 1955)': '1960',
    }.entries) {
      await fill(t, e.key, e.value);
    }
    await tap(t, find.text('중복확인'));
    expect(find.text('사용 가능한 이메일입니다.'), findsWidgets);
    await tap(t, find.text('가입하기'));
    expect(backend.requests.any((u) => u.path.endsWith('/signup')), true);
    await finish(t);
  });
  testWidgets('account password verification, save and logout confirmations', (
    t,
  ) async {
    await mount(t, const AccountSettingsPage());
    await fill(t, '닉네임', '새 닉네임');
    await tap(t, find.widgetWithText(FilledButton, '저장'));
    await fill(t, '현재 비밀번호', 'right-password');
    await tap(t, find.widgetWithText(TextButton, '확인'));
    expect(backend.profile['nickname'], '새 닉네임');
    await tap(t, find.widgetWithText(OutlinedButton, '로그아웃'));
    await tap(t, find.text('취소'));
    expect(Supabase.instance.client.auth.currentUser, isNotNull);
    await tap(t, find.widgetWithText(OutlinedButton, '로그아웃'));
    await tap(t, find.widgetWithText(TextButton, '로그아웃'));
    expect(Supabase.instance.client.auth.currentUser, isNull);
    await finish(t);
  });
  testWidgets(
    'signout clears pushed private routes and back cannot reveal them',
    (t) async {
      await mount(
        t,
        AuthGate(
          signedInPage: MainShell(
            activityRepository: FakeActivityRepository(),
            nearbyLoader: ({force = false}) async => [],
          ),
        ),
      );
      await tap(t, find.text('내 정보'));
      await tap(t, find.text('회원정보 관리'));
      expect(find.byType(AccountSettingsPage), findsOneWidget);
      await tap(t, find.widgetWithText(OutlinedButton, '로그아웃'));
      await tap(t, find.widgetWithText(TextButton, '로그아웃'));
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(AccountSettingsPage), findsNothing);
      expect(find.byType(MainShell), findsNothing);
      final navigator = t.state<NavigatorState>(find.byType(Navigator).last);
      expect(navigator.canPop(), false);
      await backend.signIn();
      await t.pumpAndSettle();
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.byType(AccountSettingsPage), findsNothing);
      await finish(t);
    },
  );
  testWidgets('five navigation destinations and profile menus open', (t) async {
    await mount(
      t,
      MainShell(
        facilityPage: const Center(child: Text('테스트 지도')),
        nearbyLoader: ({force = false}) async => [],
        activityRepository: FakeActivityRepository(),
      ),
    );
    for (final label in ['시설 찾기', '활동', '동네 모임', '커뮤니티', '홈']) {
      await tap(t, find.widgetWithText(NavigationDestination, label));
    }
    await mount(t, ProfilePage(activityRepository: FakeActivityRepository()));
    for (final label in [
      '내가 쓴 게시글',
      '내가 만든 모임',
      '회원정보 관리',
      '개인정보 처리방침',
      '나의 활동',
      '즐겨찾는 시설',
    ]) {
      await tap(t, find.text(label));
      expect(t.takeException(), isNull);
      await tap(t, find.byType(BackButton));
    }
    await finish(t);
  });
  testWidgets('community new post save returns and refreshes list', (t) async {
    await mount(t, const CommunityPage());
    await tap(t, find.text('글쓰기'));
    await fill(t, '제목', '새 동네 글');
    await fill(t, '내용', '이웃에게 알립니다');
    await tap(t, find.text('등록하기'));
    expect(backend.postWrites, 1);
    expect(find.text('새 동네 글'), findsOneWidget);
    await finish(t);
  });
  testWidgets('meetup creation validates fields and uses selected facility', (
    t,
  ) async {
    await mount(t, NewMeetupPage(facilityPicker: () async => testPlace));
    await tap(t, find.text('날짜 선택'));
    await tap(t, find.text('확인'));
    await tap(t, find.text('시간 선택'));
    await tap(t, find.text('확인'));
    await tap(t, find.text('장소 선택'));
    await fill(t, '모임 제목', '새 모임');
    await fill(t, '내용', '같이 만나요');
    await tap(t, find.text('등록하기'));
    expect(backend.postWrites, 0);
    expect(find.text('미래의 모임 시간을 선택해주세요.'), findsOneWidget);
    await tap(t, find.text('날짜'));
    final target = DateTime.now().add(const Duration(days: 2));
    if (target.month != DateTime.now().month) {
      await tap(t, find.byTooltip('다음 달'));
    }
    await tap(t, find.text('${target.day}').last);
    await tap(t, find.text('확인'));
    await tap(t, find.text('등록하기'));
    expect(backend.postWrites, 1);
    expect(backend.posts.single['facility_id'], 'facility');
    await finish(t);
  });
  testWidgets(
    'facility card remains usable at narrow width and enlarged text',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 1100));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await mount(
        t,
        const FacilitySearchPage(
          initialFacility: testPlace,
          mapPlaceholder: ColoredBox(color: Colors.blue),
          enableRealtime: false,
        ),
        scale: 2,
      );
      await tap(t, find.text('나 여기 있음'));
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
  testWidgets(
    'favorite list distinguishes a failed lookup from an empty list',
    (t) async {
      backend.failFavorites = true;
      await mount(t, const FavoriteFacilitiesPage());
      expect(find.text('즐겨찾는 시설을 불러오지 못했어요.'), findsOneWidget);
      expect(find.text('아직 즐겨찾는 시설이 없어요.'), findsNothing);
      backend.failFavorites = false;
      await tap(t, find.text('다시 시도'));
      expect(find.text('아직 즐겨찾는 시설이 없어요.'), findsOneWidget);
      await finish(t);
    },
  );
  testWidgets(
    'changing province replaces district dropdown with a valid selection',
    (t) async {
      String? district;
      await mount(
        t,
        RegionPicker(
          initialSido: '서울특별시',
          initialSigungu: '강남구',
          onChanged: (a, b) {
            district = b;
          },
        ),
      );
      await tap(t, find.text('서울특별시'));
      await tap(t, find.text('부산광역시').last);
      expect(district, kKoreaRegions['부산광역시']!.first);
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
}

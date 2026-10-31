import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/auth/signup_page.dart';
import 'package:silver_life/community/post_detail_page.dart';
import 'package:silver_life/core/terms_gate.dart';
import 'package:silver_life/profile/terms_page.dart';

import 'support/fake_backend.dart';
import 'support/widget_actions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = FakeBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.reset();
    resetTermsGate();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> fillSignup(WidgetTester t) async {
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
  }

  bool signedUp() => backend.requests.any((u) => u.path.endsWith('/signup'));

  testWidgets('signup needs both agreements and sends the terms version', (
    t,
  ) async {
    await fillSignup(t);
    await tap(t, find.text('가입하기'));
    expect(signedUp(), false);
    expect(find.text('이용약관과 개인정보 처리방침에 모두 동의해 주세요.'), findsOneWidget);

    await tap(t, find.text('[필수] 이용약관에 동의해요'));
    await tap(t, find.text('가입하기'));
    expect(signedUp(), false);

    await tap(t, find.text('[필수] 개인정보 처리방침에 동의해요'));
    await tap(t, find.text('가입하기'));
    expect(signedUp(), true);
    expect(backend.signupData?['terms_version'], kTermsVersion);
    await finish(t);
  });

  testWidgets('signup terms can be read', (t) async {
    await mount(t, const SignupPage());
    await tap(t, find.text('보기').first);
    expect(find.byType(TermsPage), findsOneWidget);
    await finish(t);
  });

  testWidgets('terms state rules, sanctions and refunds', (t) async {
    await mount(t, const TermsPage());
    final text = find
        .byType(Text)
        .evaluate()
        .map((e) => (e.widget as Text).data ?? '')
        .join('\n');
    for (final word in [
      '욕설',
      '광고',
      '사기',
      '음란물',
      '개인정보',
      '숨겨',
      '이용을 제한',
      '환불',
    ]) {
      expect(text, contains(word));
    }
    await finish(t);
  });

  Future<void> writeComment(WidgetTester t) async {
    backend.posts.add(backend.post());
    await mount(t, const PostDetailPage(postId: 'post'));
    await t.enterText(find.byType(TextField).last, '반가워요');
    await t.pump();
    await tap(t, find.byTooltip('댓글 보내기'));
  }

  testWidgets('existing member agrees once before the first comment', (
    t,
  ) async {
    backend.termsAccepted = false;
    await writeComment(t);
    expect(find.text('이용약관에 동의해 주세요'), findsOneWidget);
    expect(backend.commentWrites, 0);

    await tap(t, find.text('동의하기'));
    expect(backend.termsAccepted, true);
    expect(backend.commentWrites, 1);

    // 두 번째부터는 묻지 않는다.
    await t.enterText(find.byType(TextField).last, '또 왔어요');
    await t.pump();
    await tap(t, find.byTooltip('댓글 보내기'));
    expect(find.text('이용약관에 동의해 주세요'), findsNothing);
    expect(backend.commentWrites, 2);
    await finish(t);
  });

  testWidgets('declining keeps the comment unsent', (t) async {
    backend.termsAccepted = false;
    await writeComment(t);
    await tap(t, find.text('다음에 하기'));
    expect(backend.commentWrites, 0);
    expect(backend.termsAccepted, false);
    expect(find.text('반가워요'), findsOneWidget);
    await finish(t);
  });

  testWidgets('a member who already agreed is not asked', (t) async {
    await writeComment(t);
    expect(find.text('이용약관에 동의해 주세요'), findsNothing);
    expect(backend.commentWrites, 1);
    await finish(t);
  });
}

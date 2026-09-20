import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:silver_life/auth/login_page.dart';

void main() {
  testWidgets('login page shows app name and fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('실버라이프'), findsOneWidget);
    expect(find.text('이메일 (아이디)'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);
  });
}

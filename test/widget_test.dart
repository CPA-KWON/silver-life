import 'package:flutter_test/flutter_test.dart';

import 'package:silver_life/main.dart';

void main() {
  testWidgets('renders home page title', (WidgetTester tester) async {
    await tester.pumpWidget(const SilverLifeApp());

    expect(find.text('실버라이프'), findsWidgets);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/app_theme.dart';
import 'package:silver_life/facility/naver_local_search.dart';

const testPlace = FacilityResult(
  id: 'facility',
  name: '테스트 복지관',
  category: '복지관',
  address: '서울특별시 강남구',
  telephone: '02-123-4567',
  lat: 37.5,
  lng: 127,
  distanceMeters: 100,
);
Future<void> mount(WidgetTester t, Widget page, {double scale = 1}) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
  await t.pumpWidget(
    MaterialApp(
      theme: seniorFriendlyTheme,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(body: page),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder f) async {
  if (find.byType(SnackBar).evaluate().isNotEmpty) {
    await t.pump(const Duration(seconds: 5));
  }
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      180,
      scrollable: find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                (w.axisDirection == AxisDirection.down ||
                    w.axisDirection == AxisDirection.up),
          )
          .last,
      maxScrolls: 40,
    );
  } else {
    await t.ensureVisible(f.last);
  }
  await t.pumpAndSettle();
  await t.tap(f.last);
  await t.pumpAndSettle();
}

Future<void> fill(WidgetTester t, String label, String value) async {
  final f = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );
  await t.ensureVisible(f);
  await t.enterText(f, value);
  await t.pump();
}

Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
}

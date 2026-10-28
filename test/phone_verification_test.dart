import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:silver_life/profile/phone_verification.dart';

import 'support/widget_actions.dart';

void main() {
  test('Korean phone normalization rejects malformed input', () {
    expect(normalizeMobilePhone('010-1234-5678'), '+821012345678');
    expect(normalizeMobilePhone('+82 10 1234 5678'), '+821012345678');
    expect(normalizeMobilePhone('01012abc345678'), isNull);
    expect(normalizeMobilePhone('0101234'), isNull);
    expect(normalizeMobilePhone('821012345678'), '+821012345678');
    expect(displayMobilePhone('821012345678', mask: true), '010-****-5678');
    expect(displayMobilePhone('+821012345678', mask: true), '010-****-5678');
  });
  testWidgets(
    'code sheet verifies only six digits and never sends SMS itself',
    (t) async {
      String? submitted;
      var resends = 0;
      await mount(
        t,
        PhoneCodeSheet(
          phone: '+821012345678',
          verify: (v) async {
            submitted = v;
          },
          resend: () async {
            resends++;
          },
        ),
      );
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '6자리를 모두 입력해 주세요'),
            )
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, '인증번호 다시 받기'))
            .onPressed,
        isNull,
      );
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        await tap(t, find.widgetWithText(FilledButton, digit));
      }
      await tap(t, find.widgetWithText(FilledButton, '인증하기'));
      expect(submitted, '123456');
      expect(resends, 0);
      await finish(t);
    },
  );
  testWidgets(
    'invalid OTP retains the code and enables resend after cooldown',
    (t) async {
      var resends = 0;
      await mount(
        t,
        PhoneCodeSheet(
          phone: '+821012345678',
          verify: (_) async {
            throw const AuthException('Invalid OTP', code: 'otp_expired');
          },
          resend: () async {
            resends++;
          },
        ),
      );
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        await tap(t, find.widgetWithText(FilledButton, digit));
      }
      await tap(t, find.widgetWithText(FilledButton, '인증하기'));
      expect(find.textContaining('맞지 않거나 만료'), findsOneWidget);
      expect(find.text('다시 확인하기'), findsOneWidget);
      // Wall-clock based cooldown is tested independently of frame time; no real SMS.
      expect(resends, 0);
      await finish(t);
    },
  );
  testWidgets(
    'OTP sheet does not overflow on a narrow screen with large text',
    (t) async {
      t.view.physicalSize = const Size(320, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await mount(
        t,
        PhoneCodeSheet(
          phone: '+821012345678',
          verify: (_) async {},
          resend: () async {},
        ),
        scale: 1.25,
      );
      expect(t.takeException(), isNull);
      await finish(t);
    },
  );
}

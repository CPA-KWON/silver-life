import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';

String? normalizeMobilePhone(String value) {
  var p = value.replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^8210[0-9]{8}$').hasMatch(p)) p = '+$p';
  if (RegExp(r'^010[0-9]{8}$').hasMatch(p)) p = '+82${p.substring(1)}';
  return RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(p) ? p : null;
}

String displayMobilePhone(String phone, {bool mask = false}) {
  final normalized = normalizeMobilePhone(phone) ?? phone;
  var p = normalized.startsWith('+82')
      ? '0${normalized.substring(3)}'
      : normalized;
  if (RegExp(r'^8210[0-9]{8}$').hasMatch(p)) p = '+$p';
  if (RegExp(r'^010[0-9]{8}$').hasMatch(p)) {
    p = '${p.substring(0, 3)}-${mask ? '****' : p.substring(3, 7)}-${p.substring(7)}';
  }
  return p;
}

Future<bool?> showPhoneCodeSheet(BuildContext context, String phone) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PhoneCodeSheet(
        phone: phone,
        verify: (code) async {
          final result = await Supabase.instance.client.auth.verifyOTP(
            phone: phone,
            token: code,
            type: OtpType.phoneChange,
          );
          if (normalizeMobilePhone(result.user?.phone ?? '') !=
                  normalizeMobilePhone(phone) ||
              result.user?.phoneConfirmedAt == null) {
            throw const AuthException('휴대폰 인증을 완료하지 못했어요.');
          }
        },
        resend: () async {
          await Supabase.instance.client.auth.resend(
            phone: phone,
            type: OtpType.phoneChange,
          );
        },
      ),
    );

class PhoneCodeSheet extends StatefulWidget {
  const PhoneCodeSheet({
    super.key,
    required this.phone,
    required this.verify,
    required this.resend,
  });
  final String phone;
  final Future<void> Function(String) verify;
  final Future<void> Function() resend;
  @override
  State<PhoneCodeSheet> createState() => _PhoneCodeState();
}

class _PhoneCodeState extends State<PhoneCodeSheet> {
  String code = '', error = '';
  bool busy = false;
  int failures = 0;
  DateTime resendAt = DateTime.now().add(const Duration(seconds: 60));
  DateTime? retryAt;
  late final Timer tick = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });
  int get wait => resendAt.difference(DateTime.now()).inSeconds.clamp(0, 60);
  bool get locked => retryAt != null && retryAt!.isAfter(DateTime.now());
  @override
  void initState() {
    super.initState();
    tick;
  }

  @override
  void dispose() {
    tick.cancel();
    super.dispose();
  }

  Future<void> resend() async {
    if (busy || wait > 0 || locked) return;
    setState(() => busy = true);
    try {
      await widget.resend();
      if (mounted) {
        setState(() {
          code = '';
          error = '인증번호를 다시 보냈어요.';
          failures = 0;
          resendAt = DateTime.now().add(const Duration(seconds: 60));
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          error = authPhoneMessage(e);
          resendAt = DateTime.now().add(const Duration(seconds: 60));
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = '인증번호를 보내지 못했어요. 인터넷 연결을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (busy || code.length != 6 || locked) return;
    setState(() => busy = true);
    try {
      await widget.verify(code);
      if (mounted) Navigator.pop(context, true);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          failures++;
          error = e.code == 'otp_expired'
              ? '인증번호가 맞지 않거나 만료됐어요. 다시 받아 입력해 주세요.'
              : authPhoneMessage(e, verification: true);
          if (failures >= 5 || e.statusCode == '429') {
            retryAt = DateTime.now().add(const Duration(seconds: 60));
            error = '인증 시도가 많아요. 잠시 후 다시 시도해 주세요.';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '확인하지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('문자로 받은 6자리를 입력해 주세요', style: petText(22)),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${displayMobilePhone(widget.phone)}로 보냈어요.',
                  style: petText(14, color: PetColors.secondary),
                ),
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(c),
                  child: const Text('번호 고치기'),
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 6; i++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F7FA),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: error.isNotEmpty && failures > 0
                              ? Colors.red
                              : i == code.length
                              ? PetColors.blue
                              : const Color(0xFFD7E1E9),
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        i < code.length ? code[i] : ' ',
                        style: petText(26),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    wait > 0 ? '◷ $wait초 후 다시 받을 수 있어요' : '인증번호가 오지 않았나요?',
                    style: petText(13, color: PetColors.blue),
                  ),
                ),
                TextButton(
                  onPressed: wait > 0 || busy || locked ? null : resend,
                  child: const Text('인증번호 다시 받기'),
                ),
              ],
            ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  error,
                  style: petText(
                    15,
                    color: failures > 0 ? Colors.red : PetColors.secondary,
                  ),
                ),
              ),
            ActivityButton(
              busy
                  ? '확인 중…'
                  : locked
                  ? '잠시 후 다시 시도해 주세요'
                  : code.length < 6
                  ? '6자리를 모두 입력해 주세요'
                  : failures > 0
                  ? '다시 확인하기'
                  : '인증하기',
              onTap: busy || locked || code.length != 6 ? null : verify,
            ),
            const SizedBox(height: 14),
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', '⌫'],
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: key.isEmpty
                              ? const SizedBox(height: 52)
                              : FilledButton(
                                  onPressed: busy || locked
                                      ? null
                                      : () => setState(() {
                                          if (key == '⌫') {
                                            if (code.isNotEmpty) {
                                              code = code.substring(
                                                0,
                                                code.length - 1,
                                              );
                                            }
                                          } else if (code.length < 6) {
                                            code += key;
                                          }
                                        }),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFF1F5F8),
                                    foregroundColor: PetColors.ink,
                                    minimumSize: const Size(0, 52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                  ),
                                  child: Text(key, style: petText(24)),
                                ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String authPhoneMessage(AuthException e, {bool verification = false}) {
  if (e.statusCode == '429' || (e.code?.contains('rate_limit') ?? false)) {
    return '인증 요청이 많아요. 잠시 후 다시 시도해 주세요.';
  }
  if ([
    'phone_provider_disabled',
    'sms_send_failed',
    'hook_timeout',
    'hook_timeout_after_retry',
  ].contains(e.code)) {
    return '문자 인증을 이용할 수 없어요. 잠시 후 다시 시도해 주세요.';
  }
  if (e.code == 'phone_exists') return '이미 사용 중인 휴대폰 번호예요. 번호를 확인해 주세요.';
  return verification
      ? '인증번호가 맞지 않거나 만료됐어요. 다시 확인해 주세요.'
      : '인증번호를 보내지 못했어요. 번호를 확인한 뒤 다시 시도해 주세요.';
}

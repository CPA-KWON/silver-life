import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';

/// 회원 탈퇴: 경고 → 한 번 더 확인 → DB 함수 `delete_my_account`
/// (supabase/account_deletion.sql)가 본인 계정만 지운다. 이후 로그아웃해
/// AuthGate가 로그인 화면을 보여 준다 (sign_out.dart와 같은 방식).
Future<void> confirmAccountDeletion(BuildContext context) async {
  final warned = await _ask(
    context,
    title: '회원 탈퇴',
    message: '탈퇴하면 내가 쓴 글·댓글·모임, 포인트, 콩이가 모두 삭제되고 '
        '되돌릴 수 없어요.\n\n그래도 탈퇴하시겠어요?',
    confirmLabel: '계속하기',
  );
  if (warned != true || !context.mounted) return;

  final confirmed = await _ask(
    context,
    title: '정말 탈퇴하시겠어요?',
    message: '마지막 확인이에요. "탈퇴하기"를 누르면 바로 삭제돼요.',
    confirmLabel: '탈퇴하기',
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final client = Supabase.instance.client;
  try {
    await client.rpc('delete_my_account');
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('탈퇴하지 못했어요. 잠시 후 다시 시도해 주세요.')),
      );
    return;
  }

  // 계정이 이미 지워져 서버 로그아웃은 실패할 수 있으니 이 기기에서만 정리한다.
  try {
    await client.auth.signOut(scope: SignOutScope.local);
  } catch (_) {}
  navigator.popUntil((route) => route.isFirst);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('탈퇴가 완료되었어요. 그동안 고마웠어요.')));
}

Future<bool?> _ask(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 18, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('취소'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () => Navigator.pop(dialog, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

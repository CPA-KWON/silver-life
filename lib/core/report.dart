import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Must match the `reports.reason` check constraint in supabase/reports.sql.
const kReportReasons = ['욕설·비방', '광고', '사기 의심', '기타'];

/// Asks for a reason, then files a report against exactly one of
/// [postId] / [commentId]. Results are shown as dialogs rather than
/// SnackBars so they don't disappear before a senior user can read them.
/// Once a post/comment has 3+ reports, RLS hides it from everyone but its
/// author (see supabase/reports.sql) — nothing to filter client-side.
Future<void> showReportFlow(
  BuildContext context, {
  String? postId,
  String? commentId,
}) async {
  assert((postId == null) != (commentId == null));
  final target = postId != null ? '글' : '댓글';

  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('이 $target을 신고하는 이유를 골라주세요'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final reason in kReportReasons) ...[
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(reason),
              child: Text(reason),
            ),
            const SizedBox(height: 12),
          ],
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(fontSize: 18),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
        ],
      ),
    ),
  );
  if (reason == null || !context.mounted) return;

  final client = Supabase.instance.client;
  String title;
  String message;
  try {
    await client.from('reports').insert({
      'reporter_id': client.auth.currentUser!.id,
      'post_id': ?postId,
      'comment_id': ?commentId,
      'reason': reason,
    });
    title = '신고가 접수됐어요';
    message = '알려주셔서 고맙습니다.\n우리 팀이 확인한 뒤 조치할게요.';
  } on PostgrestException catch (e) {
    if (e.code == '23505') {
      // unique (reporter_id, post_id|comment_id) — already reported.
      title = '이미 신고하셨어요';
      message = '이 $target은 이미 신고하셨어요.\n같은 $target은 한 번만 신고할 수 있어요.';
    } else {
      title = '신고하지 못했어요';
      message = '잠시 후 다시 시도해 주세요.';
    }
  } catch (_) {
    title = '신고하지 못했어요';
    message = '인터넷 연결을 확인하고 다시 시도해 주세요.';
  }
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message, style: const TextStyle(fontSize: 18)),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

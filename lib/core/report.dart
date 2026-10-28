import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../activity/activity_design.dart';
import '../pet/pet_design.dart';

const kReportReasons = ['욕설·비방', '광고', '사기 의심', '음란·불쾌한 내용', '기타'];
Future<void> showReportFlow(
  BuildContext context, {
  String? postId,
  String? commentId,
}) async {
  assert((postId == null) != (commentId == null));
  String? selected;
  final reason = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('신고 이유를 골라 주세요', style: petText(24)),
              const SizedBox(height: 8),
              Text(
                '신고는 익명으로 처리돼요',
                style: petText(15, color: PetColors.secondary),
              ),
              const SizedBox(height: 16),
              for (final r in kReportReasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: () => set(() => selected = r),
                    icon: Icon(
                      selected == r
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    label: Text(r),
                  ),
                ),
              ActivityButton(
                '신고하기',
                color: Colors.red,
                onTap: selected == null
                    ? null
                    : () => Navigator.pop(c, selected),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  if (reason == null || !context.mounted) return;
  var title = '신고가 접수됐어요', message = '확인 후 규정에 따라 조치할게요. 알려주셔서 고맙습니다.';
  try {
    final c = Supabase.instance.client;
    await c.from('reports').insert({
      'reporter_id': c.auth.currentUser!.id,
      'post_id': ?postId,
      'comment_id': ?commentId,
      'reason': reason,
    });
  } on PostgrestException catch (e) {
    title = e.code == '23505' ? '이미 신고하셨어요' : '신고하지 못했어요';
    message = e.code == '23505'
        ? '같은 글이나 댓글은 한 번만 신고할 수 있어요.'
        : '잠시 후 다시 시도해 주세요.';
  } catch (_) {
    title = '신고하지 못했어요';
    message = '인터넷 연결을 확인한 뒤 다시 시도해 주세요.';
  }
  if (context.mounted) {
    await activityDialog(
      context,
      title: title,
      message: message,
      action: '확인',
      secondary: '닫기',
      icon: Icons.verified_outlined,
    );
  }
}

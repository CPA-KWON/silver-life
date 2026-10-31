import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../profile/privacy_policy_page.dart';
import '../profile/terms_page.dart';

String? _acceptedBy;

@visibleForTesting
void resetTermsGate() => _acceptedBy = null;

/// Called right before a new post, comment or meetup is saved. Members who joined
/// before consent was recorded (or before the terms changed) agree once here.
/// Returns false when the write must not go ahead.
Future<bool> ensureTermsAccepted(BuildContext context) async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser?.id;
  if (user == null) return false;
  if (_acceptedBy == user) return true;
  final messenger = ScaffoldMessenger.of(context);
  void failed() => messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(content: Text('약관 동의를 확인하지 못했어요. 다시 시도해 주세요.')),
    );
  try {
    final accepted = await client.rpc(
      'terms_accepted',
      params: {'p_version': kTermsVersion},
    );
    if (accepted == true) {
      _acceptedBy = user;
      return true;
    }
  } catch (_) {
    failed();
    return false;
  }
  if (!context.mounted) return false;
  final agreed = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('이용약관에 동의해 주세요'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '글·댓글·모임을 쓰려면 동의가 필요해요.\n'
            '욕설, 광고, 사기, 음란물, 다른 사람의 개인정보 공개는 금지되며, '
            '어기면 글이 숨겨지거나 이용이 제한될 수 있어요.',
            style: TextStyle(fontSize: 18, height: 1.5),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(dialog)
                    .push(MaterialPageRoute(builder: (_) => const TermsPage())),
            child: const Text('이용약관 보기'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(dialog).push(
              MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
            ),
            child: const Text('개인정보 처리방침 보기'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('다음에 하기'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('동의하기'),
        ),
      ],
    ),
  );
  if (agreed != true) return false;
  try {
    await client.rpc('accept_terms', params: {'p_version': kTermsVersion});
    _acceptedBy = user;
    return true;
  } catch (_) {
    failed();
    return false;
  }
}

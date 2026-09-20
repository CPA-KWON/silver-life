import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/region_picker.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String? _sido;
  String? _sigungu;
  late Future<Map<String, dynamic>> _profileFuture;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    _nicknameController.text = profile['nickname'] as String;
    _sido = profile['region_sido'] as String;
    _sigungu = profile['region_sigungu'] as String;
    return profile;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final password = await _promptPassword();
    if (password == null) return;

    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser!;
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: user.email!,
          password: password,
        );
      } on AuthException {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('비밀번호가 일치하지 않습니다.')));
        }
        return;
      }

      await Supabase.instance.client.from('profiles').update({
        'nickname': _nicknameController.text.trim(),
        'region_sido': _sido,
        'region_sigungu': _sigungu,
      }).eq('id', user.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final message = e.code == '23505' ? '이미 사용 중인 닉네임입니다.' : '저장에 실패했습니다: ${e.message}';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Re-verifies identity before writing a change to account info: asks for
  /// the current password, returning it on "확인" so the caller can check
  /// it against Supabase, or null if the user cancels.
  Future<String?> _promptPassword() {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => const _PasswordPromptDialog(),
    );
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
      // AuthGate swaps its built content to LoginPage once the auth state
      // stream fires, but this page was pushed on top of it via the app's
      // single shared Navigator — without popping back to that root route,
      // it would keep covering the login screen underneath.
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원정보 관리')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
          }

          final profile = snapshot.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('이름', style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            profile['name'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text('가입일', style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            (profile['created_at'] as String).split('T').first,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(labelText: '닉네임'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? '닉네임을 입력해주세요' : null,
                  ),
                  const SizedBox(height: 16),
                  RegionPicker(
                    initialSido: _sido,
                    initialSigungu: _sigungu,
                    onChanged: (sido, sigungu) {
                      _sido = sido;
                      _sigungu = sigungu;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isSaving ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('저장'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _confirmSignOut,
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog();

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    // Owned by this dialog's own State, so Flutter disposes it only once
    // the dialog is actually unmounted — not the instant showDialog's
    // Future resolves, which is before the close transition finishes and
    // would otherwise dispose it out from under the still-mounted
    // TextFormField (the "취소" crash).
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('비밀번호 확인'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: '현재 비밀번호'),
          validator: (value) => (value == null || value.isEmpty) ? '비밀번호를 입력해주세요' : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop(_controller.text);
            }
          },
          child: const Text('확인'),
        ),
      ],
    );
  }
}

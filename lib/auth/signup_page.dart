import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/korea_regions.dart';
import '../core/region_picker.dart';

// Must be registered as an intent-filter on MainActivity (see
// AndroidManifest.xml) and added to Supabase Dashboard > Authentication >
// URL Configuration > Redirect URLs, or Supabase will refuse to redirect
// here after the user confirms their email.
const _emailConfirmRedirect = 'com.silverlife.app://login-callback';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _birthYearController = TextEditingController();
  String _sido = kKoreaRegions.keys.first;
  String _sigungu = kKoreaRegions.values.first.first;
  bool _isLoading = false;
  bool _isCheckingEmail = false;
  // The email address that _emailAvailable's result applies to — any edit
  // to the email field after a check invalidates it, so a stale "사용 가능"
  // result can't carry over to a different address.
  String? _checkedEmail;
  bool? _emailAvailable;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    _nicknameController.dispose();
    _birthYearController.dispose();
    super.dispose();
  }

  Future<void> _checkEmailAvailability() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showMessage('올바른 이메일을 입력해주세요');
      return;
    }

    setState(() => _isCheckingEmail = true);
    try {
      final exists = await Supabase.instance.client.rpc(
        'email_exists',
        params: {'check_email': email},
      ) as bool;
      if (mounted) {
        setState(() {
          _checkedEmail = email;
          _emailAvailable = !exists;
        });
        _showMessage(exists ? '이미 가입된 이메일입니다.' : '사용 가능한 이메일입니다.');
      }
    } catch (_) {
      _showMessage('중복 확인에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isCheckingEmail = false);
    }
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    if (_checkedEmail != email || _emailAvailable != true) {
      _showMessage('이메일 중복확인을 먼저 진행해주세요.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: _passwordController.text,
        emailRedirectTo: _emailConfirmRedirect,
        data: {
          'name': _nameController.text.trim(),
          'nickname': _nicknameController.text.trim(),
          'region_sido': _sido,
          'region_sigungu': _sigungu,
          'birth_year': int.parse(_birthYearController.text.trim()),
        },
      );

      if (!mounted) return;

      if (response.session == null) {
        // Email confirmation is required before the user can log in.
        // Shown as a dialog (not a SnackBar) so it isn't dismissed by the
        // pop() below tearing down this page's Scaffold before it can show.
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('가입 확인 이메일 발송'),
            content: const Text(
              '입력하신 이메일 주소로 확인 메일을 보냈습니다.\n'
              '메일함에서 링크를 눌러 인증을 완료한 뒤 로그인해주세요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pop();
      }
    } on AuthException catch (e) {
      final lowerMessage = e.message.toLowerCase();
      if (lowerMessage.contains('already registered') ||
          lowerMessage.contains('already exists')) {
        // Rare race: someone else registered this exact email between the
        // 중복확인 check and this submit. Force a fresh check before retrying.
        setState(() {
          _emailAvailable = false;
          _checkedEmail = null;
        });
        _showMessage('이미 가입된 이메일입니다.');
      } else if (lowerMessage.contains('duplicate') || lowerMessage.contains('unique')) {
        // A duplicate nickname fails inside the DB trigger that creates the
        // profiles row, which GoTrue surfaces back as a generic AuthException.
        _showMessage('이미 사용 중인 닉네임입니다.');
      } else {
        _showMessage(e.message);
      }
    } catch (_) {
      _showMessage('가입 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('회원가입')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: '이메일 (아이디)',
                            helperText: _emailAvailable == null
                                ? null
                                : (_emailAvailable!
                                    ? '사용 가능한 이메일입니다.'
                                    : '이미 가입된 이메일입니다.'),
                            helperStyle: TextStyle(
                              color: _emailAvailable == true
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                          // Any edit invalidates a previous 중복확인 result —
                          // it only ever applies to the exact email it was
                          // run against.
                          onChanged: (_) => setState(() {
                            _checkedEmail = null;
                            _emailAvailable = null;
                          }),
                          validator: (value) {
                            if (value == null || !value.contains('@')) {
                              return '올바른 이메일을 입력해주세요';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton(
                          onPressed: _isCheckingEmail ? null : _checkEmailAvailability,
                          // Same theme-override reason as elsewhere in the
                          // app: a Row gives non-flex children unbounded
                          // width, and the app theme's default button
                          // minimumSize is full-width (Size.fromHeight(56)),
                          // which crashes layout if left as-is here.
                          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                          child: _isCheckingEmail
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('중복확인'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '비밀번호 (6자 이상)',
                    ),
                    validator: (value) {
                      if (value == null || value.length < 6) {
                        return '비밀번호는 6자 이상이어야 합니다';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordConfirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '비밀번호 확인',
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) {
                        return '비밀번호가 일치하지 않습니다';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '이름',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '이름을 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _nicknameController,
                    decoration: const InputDecoration(
                      labelText: '닉네임',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return '닉네임을 입력해주세요';
                      }
                      return null;
                    },
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
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _birthYearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '출생년도 (예: 1955)',
                    ),
                    validator: (value) {
                      final year = int.tryParse(value ?? '');
                      final currentYear = DateTime.now().year;
                      if (year == null || year < 1900 || year > currentYear) {
                        return '올바른 출생년도를 입력해주세요';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _isLoading ? null : _signup,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('가입하기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

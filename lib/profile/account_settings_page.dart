import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../core/region_picker.dart';
import '../social/social_form_widgets.dart';
import '../social/social_media.dart';
import 'sign_out.dart';
import 'delete_account.dart';
import 'phone_verification.dart';
import '../social/photo_widgets.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});
  @override
  State<AccountSettingsPage> createState() => _AccountState();
}

class _AccountState extends State<AccountSettingsPage> {
  final form = GlobalKey<FormState>();
  final nickname = TextEditingController(), phone = TextEditingController();
  String? sido, sigungu, avatar;
  bool busy = false, sending = false, verified = false, editingPhone = false;
  bool? phoneEnabled;
  late Future<Map<String, dynamic>> data = load();
  @override
  void initState() {
    super.initState();
    checkPhoneEnabled();
  }

  Future<void> checkPhoneEnabled() async {
    const url = String.fromEnvironment('SUPABASE_URL'),
        key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || key.isEmpty) return;
    try {
      final r = await http
          .get(Uri.parse('$url/auth/v1/settings'), headers: {'apikey': key})
          .timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as Map;
        final enabled = data['external']?['phone'];
        if (mounted && enabled is bool) setState(() => phoneEnabled = enabled);
      }
    } catch (_) {
      /* A settings lookup failure does not prevent normal account edits. */
    }
  }

  Future<Map<String, dynamic>> load() async {
    final c = Supabase.instance.client;
    final p = await c
        .from('profiles')
        .select()
        .eq('id', c.auth.currentUser!.id)
        .single();
    if (mounted) {
      nickname.text = p['nickname'] ?? '';
      sido = p['region_sido'];
      sigungu = p['region_sigungu'];
      avatar = p['avatar_path'];
      phone.text = c.auth.currentUser?.phone ?? '';
      verified =
          phone.text.isNotEmpty && c.auth.currentUser?.phoneConfirmedAt != null;
    }
    return p;
  }

  @override
  void dispose() {
    nickname.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> photo() async {
    if (busy) return;
    final source = await choosePhotoSource(context, avatar: true);
    if (source == null || !mounted) return;
    String? path;
    bool committed = false;
    try {
      if (source != PhotoSource.clear) {
        final files = await SocialMedia.chooseMany(
          limit: 1,
          camera: source == PhotoSource.camera,
        );
        if (files.isEmpty || !mounted) return;
        setState(() => busy = true);
        path = await SocialMedia.upload(files.first, folder: 'avatars');
      } else {
        setState(() => busy = true);
      }
      final c = Supabase.instance.client;
      final result = await c
          .from('profiles')
          .update({'avatar_path': path})
          .eq('id', c.auth.currentUser!.id)
          .select('id');
      if (result.isEmpty) throw StateError('사진 수정 권한이 없어요.');
      committed = true;
      final old = avatar;
      if (mounted) setState(() => avatar = path);
      if (old != null && old != path) {
        try {
          await SocialMedia.remove([old]);
        } catch (_) {
          /* Private unused image may be cleaned up later. */
        }
      }
    } catch (e) {
      // Do not delete a newly uploaded avatar after an uncertain database write:
      // the server may have committed it before the connection was lost.
      if (!committed && mounted) await photoError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendCode() async {
    if (sending || busy || phoneEnabled == false) return;
    final p = normalizeMobilePhone(phone.text);
    if (p == null) {
      await activityFailure(
        context,
        title: '휴대폰 번호를 확인해 주세요',
        message: '010으로 시작하는 번호나 국가번호를 포함해 적어 주세요.',
      );
      return;
    }
    setState(() => sending = true);
    try {
      await Supabase.instance.client.auth.updateUser(UserAttributes(phone: p));
      if (!mounted) return;
      final done = await showPhoneCodeSheet(context, p);
      if (done == true && mounted) {
        setState(() {
          phone.text = p;
          verified = true;
          editingPhone = false;
        });
        await activityDialog(
          context,
          title: '휴대폰 인증을 마쳤어요',
          message: '이제 이 번호로 회원정보가 저장돼요.',
          secondary: '',
          icon: Icons.check_circle_outline,
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        await activityFailure(
          context,
          title: '인증번호를 보내지 못했어요',
          message: authPhoneMessage(e),
        );
      }
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '인증번호를 보내지 못했어요',
          message: '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordPromptDialog(),
    );
    if (password == null || !mounted) return;
    setState(() => busy = true);
    try {
      final c = Supabase.instance.client;
      await c.auth.signInWithPassword(
        email: c.auth.currentUser!.email!,
        password: password,
      );
      await c
          .from('profiles')
          .update({
            'nickname': nickname.text.trim(),
            'region_sido': sido,
            'region_sigungu': sigungu,
          })
          .eq('id', c.auth.currentUser!.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
      }
    } on AuthException {
      if (mounted) await activityFailure(context, title: '비밀번호가 일치하지 않습니다.');
    } on PostgrestException catch (e) {
      if (mounted) {
        await activityFailure(
          context,
          title: e.code == '23505' ? '이미 사용 중인 닉네임입니다.' : '회원정보를 저장하지 못했어요',
        );
      }
    } catch (_) {
      if (mounted) await activityFailure(context, title: '회원정보를 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> changeRegion() async {
    var a = sido, b = sigungu;
    final selected = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('우리 동네 고르기', style: petText(23)),
              const SizedBox(height: 18),
              RegionPicker(
                initialSido: a,
                initialSigungu: b,
                onChanged: (x, y) {
                  a = x;
                  b = y;
                },
              ),
              const SizedBox(height: 24),
              ActivityButton(
                '이 동네로 정하기',
                onTap: () => Navigator.pop(c, (a!, b!)),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        sido = selected.$1;
        sigungu = selected.$2;
      });
    }
  }

  String _joinedDate() {
    final d = DateTime.tryParse(
      Supabase.instance.client.auth.currentUser?.createdAt ?? '',
    )?.toLocal();
    return d == null ? '' : '${d.year}년 ${d.month}월 ${d.day}일 가입';
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '회원정보 관리',
    tint: const Color(0xFFE2F0FB),
    bottom: ActivityButton(
      busy ? '저장 중…' : '저장하기',
      onTap: busy || sending ? null : save,
    ),
    child: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (c, s) => s.connectionState != ConnectionState.done
          ? const NeighborhoodLoading()
          : s.hasError
          ? ActivityEmpty(
              '회원정보를 불러오지 못했어요',
              action: '다시 시도',
              onAction: () => setState(() {
                data = load();
              }),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: ActivityCard(
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                if (avatar == null)
                                  NeighborAvatar(
                                    '${s.data!['name'] ?? nickname.text}',
                                    radius: 38,
                                    color: PetColors.orange,
                                  )
                                else
                                  ClipOval(
                                    child: SizedBox(
                                      width: 76,
                                      height: 76,
                                      child: SocialPhoto(path: avatar),
                                    ),
                                  ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Material(
                                    shape: const CircleBorder(),
                                    color: PetColors.blue,
                                    child: IconButton(
                                      tooltip: '사진 바꾸기',
                                      onPressed: busy ? null : photo,
                                      icon: const Icon(
                                        Icons.photo_camera_outlined,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                        minHeight: 40,
                                      ),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '이름',
                                    style: petText(
                                      13,
                                      color: PetColors.secondary,
                                    ),
                                  ),
                                  Text(
                                    '${s.data!['name'] ?? nickname.text}',
                                    style: petText(20),
                                  ),
                                  Text(
                                    _joinedDate(),
                                    style: petText(
                                      14,
                                      color: PetColors.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SocialFormCard(
                      '닉네임',
                      step: 1,
                      color: PetColors.blue,
                      required: true,
                      child: TextFormField(
                        controller: nickname,
                        maxLength: 10,
                        decoration: const InputDecoration(
                          labelText: '닉네임',
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        validator: (v) => v == null || v.trim().length < 2
                            ? '닉네임을 2자 이상 적어 주세요'
                            : null,
                      ),
                    ),
                    SocialFormCard(
                      '우리 동네',
                      step: 2,
                      color: PetColors.blue,
                      required: true,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.place_outlined,
                          color: PetColors.blue,
                        ),
                        title: Text(
                          '${sido ?? '시/도 선택'} ${sigungu ?? ''}',
                          style: petText(18),
                        ),
                        trailing: TextButton(
                          onPressed: busy ? null : changeRegion,
                          child: const Text('변경'),
                        ),
                      ),
                    ),
                    SocialFormCard(
                      '휴대폰 번호',
                      step: 3,
                      color: PetColors.blue,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (verified && !editingPhone) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F6FA),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFD5E1EA),
                                ),
                              ),
                              child: Wrap(
                                spacing: 12,
                                children: [
                                  Text(
                                    displayMobilePhone(phone.text, mask: true),
                                    style: petText(18),
                                  ),
                                  Text(
                                    '✓ 인증됨',
                                    style: petText(15, color: PetColors.green),
                                  ),
                                ],
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: sending || busy
                                    ? null
                                    : () => setState(() => editingPhone = true),
                                child: const Text('번호 바꾸기'),
                              ),
                            ),
                          ] else ...[
                            TextField(
                              controller: phone,
                              enabled: !sending && !busy,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: '휴대폰 번호',
                                hintText: '010-1234-5678',
                              ),
                            ),
                            const SizedBox(height: 12),
                            ActivityButton(
                              sending
                                  ? '전송 중…'
                                  : phoneEnabled == false
                                  ? '휴대폰 인증 준비 중'
                                  : '인증번호 받기',
                              onTap: sending || busy || phoneEnabled == false
                                  ? null
                                  : sendCode,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              phoneEnabled == false
                                  ? '휴대폰 인증을 준비하고 있어요. 다른 회원정보는 수정할 수 있어요.'
                                  : '인증을 마친 번호만 저장돼요.',
                              style: petText(14, color: PetColors.secondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => confirmAccountSignOut(c),
                      child: const Text('로그아웃'),
                    ),
                    TextButton(
                      onPressed: () => confirmAccountDeletion(c),
                      child: const Text(
                        '회원 탈퇴',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
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
          validator: (value) =>
              (value == null || value.isEmpty) ? '비밀번호를 입력해주세요' : null,
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

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../social/neighborhood_repository.dart';
import '../social/social_media.dart';
import 'app_preferences.dart';

class ReadingSettingsPage extends StatelessWidget {
  const ReadingSettingsPage({super.key});
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: AppPreferences.instance,
    builder: (c, _) => NeighborhoodScreen(
      title: '알림·글씨 크기',
      tint: const Color(0xFFE6F2FC),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const NeighborhoodHeading('글씨 크기'),
          ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in [
                      ('보통', 1.0),
                      ('크게', 1.15),
                      ('아주 크게', 1.25),
                    ])
                      ChoiceChip(
                        label: Text(v.$1),
                        selected: AppPreferences.instance.fontScale == v.$2,
                        onSelected: (_) => AppPreferences.instance.font(v.$2),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text('이렇게 보여요. 큰 글씨로 동네 활동을 찾아보세요.', style: petText(18)),
              ],
            ),
          ),
          const NeighborhoodHeading('알림'),
          ActivityCard(
            child: Column(
              children: [
                for (final e in AppPreferences.instance.alerts.entries)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(e.key, style: petText(17)),
                    value: e.value,
                    onChanged: (v) async {
                      if (v) {
                        final status = await Permission.notification.request();
                        if (!status.isGranted && c.mounted) {
                          await activityDialog(
                            c,
                            title: '알림 권한이 필요해요',
                            message: '휴대폰 설정에서 알림을 허용해 주세요.',
                            action: '확인',
                          );
                          return;
                        }
                      }
                      await AppPreferences.instance.alert(e.key, v);
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ActivityButton('휴대폰 알림 설정 열기', light: true, onTap: openAppSettings),
        ],
      ),
    ),
  );
}

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});
  @override
  State<BlockedUsersPage> createState() => _BlocksState();
}

class _BlocksState extends State<BlockedUsersPage> {
  late Future<List<SocialData>> data = NeighborhoodRepository().blocks();
  void reload() => setState(() {
    data = NeighborhoodRepository().blocks();
  });
  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '차단한 사용자',
    tint: const Color(0xFFE6F2FC),
    child: FutureBuilder<List<SocialData>>(
      future: data,
      builder: (c, s) => s.connectionState != ConnectionState.done
          ? const NeighborhoodLoading()
          : s.hasError
          ? ActivityEmpty('차단 목록을 불러오지 못했어요', action: '다시 시도', onAction: reload)
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '차단한 분의 글과 댓글이 보이지 않아요.',
                  style: petText(16, color: PetColors.secondary),
                ),
                const SizedBox(height: 14),
                if (s.data!.isEmpty)
                  const ActivityEmpty(
                    '차단한 사용자가 없어요',
                    icon: Icons.verified_user_outlined,
                  ),
                for (final p in s.data!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ActivityCard(
                      child: Row(
                        children: [
                          NeighborAvatar('${p['nickname']}'),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('${p['nickname']}', style: petText(18)),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await NeighborhoodRepository().unblock(
                                  p['blocked_id'],
                                );
                                if (mounted) reload();
                              } catch (_) {
                                if (c.mounted) {
                                  await activityFailure(
                                    c,
                                    title: '차단을 해제하지 못했어요',
                                  );
                                }
                              }
                            },
                            child: const Text('차단 해제'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    ),
  );
}

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});
  @override
  State<DeleteAccountPage> createState() => _DeleteState();
}

class _DeleteState extends State<DeleteAccountPage> {
  String? reason;
  bool agreed = false, busy = false;
  final password = TextEditingController();
  @override
  void dispose() {
    password.dispose();
    super.dispose();
  }

  Future<void> remove() async {
    if (!agreed || reason == null || busy || password.text.isEmpty) return;
    if (!await activityDialog(
      context,
      title: '정말 탈퇴할까요?',
      message: '회원 정보와 작성한 글·댓글·콩이 기록·포인트가 삭제돼요. 복구할 수 없어요.',
      action: '탈퇴하기',
      color: Colors.red,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      final c = Supabase.instance.client,
          uid = c.auth.currentUser!.id,
          email = c.auth.currentUser!.email!;
      await c.auth.signInWithPassword(email: email, password: password.text);
      try {
        for (final folder in ['posts', 'avatars', 'org-proofs']) {
          while (true) {
            final objects = await c.storage
                .from(SocialMedia.bucket)
                .list(
                  path: '$uid/$folder',
                  searchOptions: const SearchOptions(limit: 100),
                );
            if (objects.isEmpty) break;
            await SocialMedia.remove([
              for (final o in objects) '$uid/$folder/${o.name}',
            ]);
          }
        }
      } on StorageException catch (e) {
        // Existing accounts may predate the private-photo bucket.
        if (e.statusCode != '404') rethrow;
      }
      await c.rpc('delete_my_account');
      // Account deletion already committed. A local cleanup failure must never
      // misreport it as an incorrect password or claim the account still exists.
      try {
        await c.auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        if (mounted) {
          await activityFailure(
            context,
            title: '계정은 삭제됐어요',
            message: '앱을 완전히 닫은 뒤 다시 열어 주세요.',
          );
        }
        return;
      }
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on AuthException {
      if (mounted) await activityFailure(context, title: '비밀번호를 확인해 주세요');
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '탈퇴하지 못했어요',
          message: '연결이 끊겨 결과를 확인하지 못했어요. 다시 로그인해 계정 상태를 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '회원 탈퇴',
    tint: const Color(0xFFFFEDED),
    bottom: ActivityButton(
      '탈퇴하기',
      color: Colors.red,
      onTap: agreed && reason != null && password.text.isNotEmpty && !busy
          ? remove
          : null,
    ),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ActivityCard(
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 14),
              Text('탈퇴하면 되돌릴 수 없어요', style: petText(22, color: Colors.red)),
              Text(
                '회원 정보, 작성한 글과 댓글, 콩이와 활동·포인트 기록이 삭제돼요.',
                textAlign: TextAlign.center,
                style: petText(17, color: PetColors.secondary),
              ),
            ],
          ),
        ),
        const NeighborhoodHeading('떠나시는 이유를 알려 주세요'),
        RadioGroup<String>(
          groupValue: reason,
          onChanged: (v) => setState(() => reason = v),
          child: Column(
            children: [
              for (final r in [
                '쓰기 어려워요',
                '자주 안 써요',
                '다른 앱을 써요',
                '개인정보가 걱정돼요',
                '기타',
              ])
                RadioListTile<String>(title: Text(r), value: r),
            ],
          ),
        ),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: '현재 비밀번호'),
          onChanged: (_) => setState(() {}),
        ),
        CheckboxListTile(
          value: agreed,
          onChanged: (v) => setState(() => agreed = v ?? false),
          title: const Text('삭제되는 내용을 확인했어요'),
        ),
      ],
    ),
  );
}

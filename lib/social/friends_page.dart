import 'package:flutter/material.dart';

import '../activity/activity_widgets.dart' show activityMessage;
import '../core/report.dart';
import '../core/time_ago.dart';
import '../ui/neighborhood_design.dart';
import 'friends_repository.dart';

typedef _FriendsData = ({List<FriendData> presence, List<FriendData> people});

/// 친구 추가 + "친구는 지금 어디에?" 화면.
/// 내 정보 > 내 활동 > 친구 에서 들어옵니다.
class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key, this.repository, this.now});
  final FriendsRepository? repository;

  /// 테스트에서 "몇 분 전" 표시를 고정하기 위한 현재 시각
  final DateTime Function()? now;
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  late final FriendsRepository repo = widget.repository ?? FriendsRepository();
  late Future<_FriendsData> data = load();
  final nickname = TextEditingController();
  bool busy = false;
  bool share = true;

  @override
  void dispose() {
    nickname.dispose();
    super.dispose();
  }

  Future<_FriendsData> load() async {
    final r = await Future.wait<Object>([
      repo.presence(),
      repo.list(),
      repo.shareEnabled(),
    ]);
    share = r[2] as bool;
    return (
      presence: r[0] as List<FriendData>,
      people: r[1] as List<FriendData>,
    );
  }

  Future<void> reload() async {
    final f = load();
    setState(() {
      data = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  /// 서버 작업 하나를 실행하고, 끝나면 목록을 새로 불러옵니다. 실패하면 쉬운 안내를 보여줍니다.
  Future<void> run(
    Future<void> Function() job, {
    required String failure,
    String? done,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await job();
      if (!mounted) return;
      if (done != null) activityMessage(context, done);
      await reload();
    } catch (e) {
      if (mounted) {
        await activityDialog(
          context,
          title: failure,
          message: friendsErrorMessage(e),
          icon: Icons.info_outline,
          secondary: '닫기',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sendRequest() async {
    final name = nickname.text.trim();
    if (busy) return;
    if (name.isEmpty) {
      activityMessage(context, '친구의 닉네임을 입력해 주세요');
      return;
    }
    await run(() async {
      final result = await repo.request(name);
      nickname.clear();
      if (mounted) {
        activityMessage(
          context,
          result == 'accepted' ? '$name 님과 친구가 됐어요' : '$name 님에게 친구 요청을 보냈어요',
        );
      }
    }, failure: '친구 요청을 보내지 못했어요');
  }

  Future<void> unfriend(FriendData p) async {
    final ok = await activityDialog(
      context,
      title: '${p['nickname']} 님과 친구를 끊을까요?',
      message: '서로의 친구 목록에서 사라지고, 체크인도 더 이상 보이지 않아요.',
      action: '친구 끊기',
      icon: Icons.person_remove_outlined,
    );
    if (!ok || !mounted) return;
    await run(
      () => repo.remove('${p['friendship_id']}'),
      failure: '친구를 끊지 못했어요',
    );
  }

  Future<void> toggleShare(bool value) async {
    if (busy) return;
    final before = share;
    setState(() {
      share = value;
      busy = true;
    });
    try {
      await repo.setShare(value);
    } catch (e) {
      if (mounted) {
        setState(() => share = before);
        await activityDialog(
          context,
          title: '설정을 바꾸지 못했어요',
          message: friendsErrorMessage(e),
          icon: Icons.info_outline,
          secondary: '닫기',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String region(FriendData p) => [
    p['region_sido'],
    p['region_sigungu'],
  ].where((v) => v != null && '$v'.trim().isNotEmpty).join(' ');

  String when(FriendData p) {
    final at = DateTime.tryParse('${p['checked_in_at']}')?.toLocal();
    return at == null ? '' : '${timeAgo(at, now: widget.now?.call())} 체크인';
  }

  Widget presenceCard(FriendData p) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ActivityCard(
      color: neighborhoodMint,
      child: Row(
        children: [
          const Icon(Icons.location_on, color: PetColors.green, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['nickname']} 님', style: petText(21)),
                Text(
                  '${p['facility_name']}',
                  style: petText(19, color: PetColors.green),
                ),
                if (when(p).isNotEmpty)
                  Text(
                    when(p),
                    style: petText(
                      16,
                      color: PetColors.secondary,
                      weight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget person(FriendData p, List<Widget> actions) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: ActivityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NeighborAvatar('${p['nickname']}'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['nickname']}', style: petText(20)),
                    if (region(p).isNotEmpty)
                      Text(
                        region(p),
                        style: petText(
                          15,
                          color: PetColors.secondary,
                          weight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: actions[i]),
              ],
            ],
          ),
          if (ReportUserButton.canReport(p))
            Align(
              alignment: Alignment.centerRight,
              child: ReportUserButton(nickname: '${p['nickname']}'),
            ),
        ],
      ),
    ),
  );

  Widget body(_FriendsData d) {
    final incoming = [
      for (final p in d.people)
        if (p['relation'] == 'incoming') p,
    ];
    final friends = [
      for (final p in d.people)
        if (p['relation'] == 'friend') p,
    ];
    final outgoing = [
      for (final p in d.people)
        if (p['relation'] == 'outgoing') p,
    ];
    return RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          NeighborhoodHeading(
            '친구는 지금 어디에?',
            count: d.presence.isEmpty ? null : '${d.presence.length}명',
          ),
          if (d.presence.isEmpty)
            ActivityEmpty(
              '지금 시설에 있는 친구가 없어요',
              message: friends.isEmpty
                  ? '친구를 추가하면, 친구가 시설에서 체크인할 때 여기에 보여요.'
                  : '친구가 시설에서 체크인하면 여기에 보여요. 화면을 아래로 당기면 새로 불러와요.',
              icon: Icons.location_searching,
            )
          else
            for (final p in d.presence) presenceCard(p),
          if (incoming.isNotEmpty) ...[
            NeighborhoodHeading(
              '받은 친구 요청',
              count: '${incoming.length}명',
              color: PetColors.orange,
            ),
            for (final p in incoming)
              person(p, [
                ActivityButton(
                  '수락',
                  icon: Icons.check,
                  onTap: busy
                      ? null
                      : () => run(
                          () => repo.respond('${p['friendship_id']}', true),
                          failure: '요청을 수락하지 못했어요',
                          done: '${p['nickname']} 님과 친구가 됐어요',
                        ),
                ),
                ActivityButton(
                  '거절',
                  light: true,
                  onTap: busy
                      ? null
                      : () => run(
                          () => repo.respond('${p['friendship_id']}', false),
                          failure: '요청을 거절하지 못했어요',
                        ),
                ),
              ]),
          ],
          const NeighborhoodHeading('친구 추가'),
          ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nickname,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => sendRequest(),
                  style: petText(19),
                  decoration: const InputDecoration(
                    labelText: '친구 닉네임',
                    hintText: '친구의 닉네임을 정확히 적어 주세요',
                  ),
                ),
                const SizedBox(height: 14),
                ActivityButton(
                  '친구 요청 보내기',
                  icon: Icons.person_add_alt_1,
                  onTap: busy ? null : sendRequest,
                ),
              ],
            ),
          ),
          NeighborhoodHeading(
            '내 친구',
            count: friends.isEmpty ? null : '${friends.length}명',
          ),
          if (friends.isEmpty)
            const ActivityEmpty(
              '아직 친구가 없어요',
              message: '위에 친구의 닉네임을 적어 요청을 보내 보세요.',
              icon: Icons.group_add_outlined,
            )
          else
            for (final p in friends)
              person(p, [
                ActivityButton(
                  '친구 끊기',
                  light: true,
                  onTap: busy ? null : () => unfriend(p),
                ),
              ]),
          if (outgoing.isNotEmpty) ...[
            NeighborhoodHeading(
              '보낸 친구 요청',
              count: '${outgoing.length}명',
              color: PetColors.purple,
            ),
            for (final p in outgoing)
              person(p, [
                ActivityButton(
                  '요청 취소',
                  light: true,
                  onTap: busy
                      ? null
                      : () => run(
                          () => repo.remove('${p['friendship_id']}'),
                          failure: '요청을 취소하지 못했어요',
                        ),
                ),
              ]),
          ],
          const NeighborhoodHeading('내 체크인 공개'),
          ActivityCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: share,
              onChanged: busy ? null : toggleShare,
              title: Text('친구에게 내 체크인 보이기', style: petText(19)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '켜 두면 친구로 수락된 분에게만, 내가 체크인한 시설 이름이 최근 3시간 동안 보여요. 끄면 친구에게도 보이지 않아요.',
                  style: petText(
                    16,
                    color: PetColors.secondary,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => NeighborhoodScreen(
    title: '친구',
    subtitle: '친구가 시설에 체크인하면 여기서 볼 수 있어요',
    child: FutureBuilder<_FriendsData>(
      future: data,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const NeighborhoodLoading();
        }
        if (s.hasError) {
          final notReady = friendsNotReady(s.error!);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ActivityEmpty(
                notReady ? '친구 기능을 준비 중이에요' : '친구 정보를 불러오지 못했어요',
                message: notReady
                    ? '조금 뒤에 다시 열어 주세요.'
                    : '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
                icon: notReady ? Icons.construction_outlined : Icons.wifi_off,
                error: !notReady,
                action: '다시 시도',
                onAction: reload,
              ),
            ],
          );
        }
        return body(s.data!);
      },
    ),
  );
}

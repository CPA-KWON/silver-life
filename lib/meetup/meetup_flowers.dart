import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../attendance/attendance_controller.dart';
import '../ui/neighborhood_design.dart';

const kFlowerErrorMessage = '처리하지 못했어요. 다시 시도해 주세요.';

/// Participants of a finished meetup with flower counts, from the
/// `meetup_participation` DB function (supabase/flower_gift.sql).
Future<List<Map<String, dynamic>>> _loadParticipants(String postId) async {
  final data = await Supabase.instance.client.rpc(
    'meetup_participation',
    params: {'p_post': postId},
  );
  return [
    for (final row in (data as Map)['participants'] as List)
      Map<String, dynamic>.from(row as Map),
  ];
}

/// Participant list with "받은 꽃 ○송이" and a 1P "꽃 보내기" button next to
/// everyone the signed-in user may still thank. The server decides who that is
/// and enforces every rule again when a flower is sent.
class MeetupFlowersCard extends StatefulWidget {
  const MeetupFlowersCard({super.key, required this.postId});

  final String postId;

  @override
  State<MeetupFlowersCard> createState() => _MeetupFlowersCardState();
}

class _MeetupFlowersCardState extends State<MeetupFlowersCard> {
  late Future<List<Map<String, dynamic>>> _future = _loadParticipants(
    widget.postId,
  );
  bool _busy = false;

  void _reload() {
    setState(() {
      _future = _loadParticipants(widget.postId);
    });
  }

  Future<void> _send(Map<String, dynamic> person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('고마워요 꽃을 보낼까요?'),
        content: Text(
          '${person['nickname']}님에게 꽃 한 송이를 보내요.\n내 포인트 1P가 차감돼요.',
          style: const TextStyle(fontSize: 18, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('보내기'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final attendance = AttendanceScope.maybeOf(context);
    setState(() => _busy = true);
    var message = '${person['nickname']}님에게 꽃을 보냈어요.';
    try {
      await Supabase.instance.client.rpc(
        'send_meetup_flower',
        params: {'p_post': widget.postId, 'p_to': person['user_id']},
      );
      await attendance?.refresh();
    } on PostgrestException catch (e) {
      // DB 함수가 이유를 쉬운 말로 알려준다(포인트가 부족해요 등).
      message = e.code == 'P0001' ? e.message : kFlowerErrorMessage;
    } catch (_) {
      message = kFlowerErrorMessage;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _row(Map<String, dynamic> person) {
    final suffix = person['is_host'] == true
        ? ' (모임장)'
        : person['is_me'] == true
        ? ' (나)'
        : '';
    final flowers = person['flowers'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NeighborAvatar('${person['nickname']}', radius: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${person['nickname']}$suffix', style: petText(18)),
                    if (flowers != null)
                      Text(
                        '받은 꽃 $flowers송이',
                        style: petText(
                          18,
                          color: PetColors.secondary,
                          weight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (person['can_send_flower'] == true && person['user_id'] != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
              onPressed: _busy ? null : () => _send(person),
              icon: const Icon(Icons.local_florist_outlined),
              label: const Text('꽃 보내기 (1P)'),
            )
          else if (person['flower_sent'] == true)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, color: PetColors.green),
                const SizedBox(width: 6),
                Text('보냈어요', style: petText(18, color: PetColors.green)),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ActivityCard(
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('참여 현황을 불러오지 못했어요. 다시 시도해 주세요.', style: petText(18)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('다시 불러오기')),
            ],
          );
        }
        final people = snapshot.data;
        if (people == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final person in people) _row(person)],
        );
      },
    ),
  );
}

/// "받은 꽃": who thanked me, for which meetup and when (`my_flowers`).
/// Sender names come from public_profiles only.
class MyFlowersPage extends StatefulWidget {
  const MyFlowersPage({super.key});

  @override
  State<MyFlowersPage> createState() => _MyFlowersPageState();
}

class _MyFlowersPageState extends State<MyFlowersPage> {
  late Future<List<Map<String, dynamic>>> _future = _load();

  Future<List<Map<String, dynamic>>> _load() async {
    final data = await Supabase.instance.client.rpc('my_flowers');
    return [
      for (final row in data as List) Map<String, dynamic>.from(row as Map),
    ];
  }

  String _date(Object? iso) {
    final at = DateTime.tryParse('$iso')?.toLocal();
    return at == null ? '날짜 확인 필요' : '${at.year}년 ${at.month}월 ${at.day}일';
  }

  Widget _message(String text, {bool retry = false}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center, style: petText(18)),
          if (retry) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => setState(() {
                _future = _load();
              }),
              child: const Text('다시 불러오기'),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('받은 꽃')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _message('받은 꽃을 불러오지 못했어요. 다시 시도해 주세요.', retry: true);
        }
        final flowers = snapshot.data;
        if (flowers == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (flowers.isEmpty) {
          return _message('아직 받은 꽃이 없어요.\n모임에 함께하면 이웃에게 꽃을 받을 수 있어요.');
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Text('받은 꽃 ${flowers.length}송이', style: petText(22)),
            const SizedBox(height: 12),
            for (final flower in flowers)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ActivityCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.local_florist,
                        color: PetColors.pink,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${flower['sender_nickname']}님이 보낸 꽃',
                              style: petText(18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${flower['meetup_title']}',
                              style: petText(18, weight: FontWeight.w500),
                            ),
                            Text(
                              _date(flower['event_at']),
                              style: petText(
                                18,
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
              ),
          ],
        );
      },
    ),
  );
}

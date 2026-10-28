import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../ui/design_widgets.dart';

/// One meetup's participation state from the `meetup_participation` DB
/// function (supabase/meetup_participation.sql). Nicknames only — the
/// function reads public_profiles, never names or birth years.
class MeetupParticipation {
  const MeetupParticipation({
    required this.count,
    required this.maxParticipants,
    required this.joined,
    required this.isHost,
    required this.isPast,
    required this.participants,
  });

  factory MeetupParticipation.fromJson(Map<String, dynamic> json) =>
      MeetupParticipation(
        count: (json['count'] as num).toInt(),
        maxParticipants: (json['max_participants'] as num).toInt(),
        joined: json['joined'] as bool,
        isHost: json['is_host'] as bool,
        isPast: json['is_past'] as bool,
        participants: [
          for (final p in json['participants'] as List)
            MeetupParticipant.fromJson(p as Map<String, dynamic>),
        ],
      );

  final int count;
  final int maxParticipants;
  final bool joined;
  final bool isHost;
  final bool isPast;
  final List<MeetupParticipant> participants;

  bool get isFull => count >= maxParticipants;
}

class MeetupParticipant {
  const MeetupParticipant({
    required this.nickname,
    required this.isHost,
    required this.isMe,
  });

  factory MeetupParticipant.fromJson(Map<String, dynamic> json) =>
      MeetupParticipant(
        nickname: json['nickname'] as String,
        isHost: json['is_host'] as bool,
        isMe: json['is_me'] as bool,
      );

  final String nickname;
  final bool isHost;
  final bool isMe;
}

/// "참여자 ○명 / 최대 ○명", nickname list and the join / leave button on the
/// meetup detail screen. Joining and leaving go through DB functions only,
/// which lock the meetup row so two people can't take the last seat.
class MeetupParticipationCard extends StatefulWidget {
  const MeetupParticipationCard({super.key, required this.postId});

  final String postId;

  @override
  State<MeetupParticipationCard> createState() =>
      _MeetupParticipationCardState();
}

class _MeetupParticipationCardState extends State<MeetupParticipationCard> {
  late Future<MeetupParticipation> _future = _load();
  bool _busy = false;

  Future<MeetupParticipation> _load() async {
    final data = await Supabase.instance.client.rpc(
      'meetup_participation',
      params: {'p_post': widget.postId},
    );
    return MeetupParticipation.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<void> _join() => _run('meetup_join', '모임에 참여했어요.');

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('참여를 취소하시겠어요?'),
        content: const Text(
          '자리가 남아 있으면 다시 참여할 수 있어요.',
          style: TextStyle(fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('아니요'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('참여 취소'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run('meetup_leave', '참여를 취소했어요.');
  }

  Future<void> _run(String function, String doneMessage) async {
    setState(() => _busy = true);
    String message = doneMessage;
    try {
      await Supabase.instance.client.rpc(
        function,
        params: {'p_post': widget.postId},
      );
    } on PostgrestException catch (e) {
      // DB 함수가 이유를 쉬운 한국어로 알려준다(모집 마감, 지난 모임 등).
      message = e.code == 'P0001'
          ? e.message
          : '처리하지 못했어요. 다시 시도해 주세요.';
    } catch (_) {
      message = '처리하지 못했어요. 다시 시도해 주세요.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _future = _load();
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FutureBuilder<MeetupParticipation>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return SectionCard(
            padding: const EdgeInsets.all(20),
            child: snapshot.hasError
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '참여 정보를 불러오지 못했어요. 다시 시도해 주세요.',
                        style: textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => setState(() => _future = _load()),
                        child: const Text('다시 불러오기'),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        }
        return SectionCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.groups_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '참여자 ${data.count}명 / 최대 ${data.maxParticipants}명',
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in data.participants) _ParticipantChip(p),
                ],
              ),
              const SizedBox(height: 16),
              _actionButton(data),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton(MeetupParticipation data) {
    if (data.isHost) {
      return const _Notice('모임장은 자동으로 참여해요.');
    }
    if (data.isPast) {
      return const FilledButton(onPressed: null, child: Text('지난 모임'));
    }
    if (data.joined) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          side: const BorderSide(color: AppColors.danger),
        ),
        onPressed: _busy ? null : _leave,
        child: const Text('참여 취소'),
      );
    }
    if (data.isFull) {
      return const FilledButton(onPressed: null, child: Text('모집 마감'));
    }
    return FilledButton.icon(
      onPressed: _busy ? null : _join,
      icon: const Icon(Icons.how_to_reg),
      label: const Text('참여하기'),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  const _ParticipantChip(this.participant);

  final MeetupParticipant participant;

  @override
  Widget build(BuildContext context) {
    final label = [
      participant.nickname,
      if (participant.isHost) '(모임장)',
      if (participant.isMe && !participant.isHost) '(나)',
    ].join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: participant.isHost ? AppColors.blueTint : AppColors.neutralTint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 18,
          fontWeight: participant.isHost ? FontWeight.w700 : FontWeight.w500,
          color: participant.isHost ? AppColors.blueText : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.mintTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.mintText,
        ),
      ),
    );
  }
}

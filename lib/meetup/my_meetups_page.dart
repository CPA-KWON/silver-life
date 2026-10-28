import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../community/post_detail_page.dart';
import '../ui/design_widgets.dart';

/// Meetups the signed-in user joined (host included), from the `my_meetups`
/// DB function: upcoming ones first by date, then past ones.
Future<List<Map<String, dynamic>>> loadMyMeetups() async {
  final data = await Supabase.instance.client.rpc('my_meetups');
  return [
    for (final row in data as List) Map<String, dynamic>.from(row as Map),
  ];
}

bool isUpcomingMeetup(Map<String, dynamic> meetup) {
  final at = DateTime.tryParse(meetup['event_at'] as String? ?? '');
  return at != null && at.isAfter(DateTime.now());
}

String meetupWhen(String? iso) {
  final at = DateTime.tryParse(iso ?? '')?.toLocal();
  if (at == null) return '';
  final minute = at.minute.toString().padLeft(2, '0');
  return '${at.month}월 ${at.day}일 ${at.hour}:$minute';
}

class MyMeetupsPage extends StatefulWidget {
  const MyMeetupsPage({super.key});

  @override
  State<MyMeetupsPage> createState() => _MyMeetupsPageState();
}

class _MyMeetupsPageState extends State<MyMeetupsPage> {
  late Future<List<Map<String, dynamic>>> _future = loadMyMeetups();

  void _refresh() {
    if (mounted) setState(() => _future = loadMyMeetups());
  }

  Widget _message(String text, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (retry) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _refresh, child: const Text('다시 불러오기')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, dynamic> meetup) {
    final textTheme = Theme.of(context).textTheme;
    final upcoming = isUpcomingMeetup(meetup);
    final place = meetup['facility_name'] as String? ?? '장소 확인';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostDetailPage(postId: meetup['id'] as String),
          ),
        );
        _refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                StatusPill(
                  label: upcoming ? '예정' : '지난 모임',
                  tone: upcoming
                      ? StatusPillTone.success
                      : StatusPillTone.neutral,
                ),
                if (meetup['is_host'] == true)
                  const StatusPill(label: '모임장', tone: StatusPillTone.primary),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              meetup['title'] as String? ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              '${meetupWhen(meetup['event_at'] as String?)} · $place',
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 18,
                color: AppColors.scheduleText,
              ),
            ),
            Text(
              '참여자 ${meetup['count']}명 / 최대 ${meetup['max_participants']}명',
              style: textTheme.bodyMedium?.copyWith(
                fontSize: 18,
                color: AppColors.scheduleText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('참여한 모임')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _message('불러오지 못했어요. 다시 시도해 주세요.', retry: true);
          }
          final meetups = snapshot.data ?? [];
          if (meetups.isEmpty) {
            return _message('아직 참여한 모임이 없어요.\n동네 모임 탭에서 모임을 찾아보세요.');
          }
          final upcoming = meetups.where(isUpcomingMeetup).toList();
          final past = meetups.where((m) => !isUpcomingMeetup(m)).toList();
          final textTheme = Theme.of(context).textTheme;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final (title, rows) in [
                  ('다가오는 모임', upcoming),
                  ('지난 모임', past),
                ])
                  if (rows.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(title, style: textTheme.titleMedium),
                    ),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [for (final m in rows) _row(m)],
                      ),
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

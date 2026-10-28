import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';
import '../social/neighborhood_feed.dart' show socialTime;
import '../social/neighborhood_repository.dart';
import '../ui/neighborhood_design.dart';
import 'meetup_page.dart';
import 'new_meetup_page.dart';

Future<List<Map<String, dynamic>>> loadMyMeetups() async {
  final data = await Supabase.instance.client.rpc('my_meetups');
  return [
    for (final row in data as List) Map<String, dynamic>.from(row as Map),
  ];
}

bool isUpcomingMeetup(Map<String, dynamic> meetup) {
  final at = DateTime.tryParse(meetup['event_at'] as String? ?? '');
  return meetup['meetup_cancelled'] != true &&
      meetup['participation_cancelled'] != true &&
      at != null &&
      at.isAfter(DateTime.now());
}

String meetupWhen(String? iso) {
  final at = DateTime.tryParse(iso ?? '')?.toLocal();
  if (at == null) return '시간 확인 필요';
  return '${at.month}월 ${at.day}일 ${socialTime(iso!)}';
}

class MyMeetupsPage extends StatefulWidget {
  const MyMeetupsPage({super.key});
  @override
  State<MyMeetupsPage> createState() => _MyMeetupsPageState();
}

class _MyMeetupsPageState extends State<MyMeetupsPage> {
  late Future<List<Map<String, dynamic>>> _future = loadMyMeetups();
  bool past = false;
  Future<List<Map<String, dynamic>>>? nearby;
  Future<List<Map<String, dynamic>>> loadNearby() async {
    final c = Supabase.instance.client;
    final profile = await c
        .from('profiles')
        .select('region_sido,region_sigungu')
        .eq('id', c.auth.currentUser!.id)
        .single();
    if (profile['region_sido'] == null || profile['region_sigungu'] == null) {
      return [];
    }
    final now = DateTime.now();
    final end = DateUtils.dateOnly(now).add(Duration(days: 8 - now.weekday));
    final values = List<Map<String, dynamic>>.from(
      await c
          .from('posts')
          .select('*,facilities!inner(name,region_sido,region_sigungu)')
          .eq('category', '동네모임')
          .eq('facilities.region_sido', profile['region_sido'])
          .eq('facilities.region_sigungu', profile['region_sigungu'])
          .gt('event_at', now.toUtc().toIso8601String())
          .lt('event_at', end.toUtc().toIso8601String())
          .order('event_at')
          .limit(10),
    );
    final rows = values
        .where((p) => p['meetup_cancelled'] != true)
        .take(3)
        .toList();
    await NeighborhoodRepository().enrich(rows);
    return [
      for (final p in rows)
        {
          ...p,
          'facility_name': p['facilities']?['name'],
          'count': p['member_count'],
        },
    ];
  }

  Future<void> _refresh() async {
    nearby = null;
    final f = loadMyMeetups();
    setState(() {
      _future = f;
    });
    try {
      await f;
    } catch (_) {
      /* FutureBuilder keeps retry state. */
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  Widget _tabs(List<Map<String, dynamic>>? rows) => ActivityCard(
    padding: 5,
    child: Row(
      children: [
        for (final value in [false, true])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ActivityButton(
                '${value ? '지난 모임' : '예정'}${rows == null ? '' : ' ${rows.where((m) => isUpcomingMeetup(m) != value).length}'}',
                light: past != value,
                onTap: () => setState(() => past = value),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _row(Map<String, dynamic> m) {
    final date = DateTime.tryParse('${m['event_at']}')?.toLocal();
    final cancelled = m['participation_cancelled'] == true;
    final upcoming = isUpcomingMeetup(m);
    final members = List<Map<String, dynamic>>.from(m['participants'] ?? []);
    final topic = m['meetup_topic'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ActivityCard(
        onTap: () => open(PostDetailPage(postId: m['id'] as String)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: upcoming ? neighborhoodMint : const Color(0xFFEDF1F4),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Text(
                    date == null ? '-' : '${date.month}월',
                    style: petText(13, color: PetColors.secondary),
                  ),
                  Text(
                    date == null ? '-' : '${date.day}',
                    style: petText(
                      29,
                      color: upcoming ? PetColors.green : PetColors.secondary,
                    ),
                  ),
                  if (date != null)
                    Text(
                      ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1],
                      style: petText(13, color: PetColors.secondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      if (topic != null && topic.isNotEmpty)
                        PetPill(
                          topic,
                          color: neighborhoodMint,
                          ink: PetColors.green,
                        ),
                      PetPill(
                        cancelled
                            ? '참여 취소'
                            : m['meetup_cancelled'] == true
                            ? '취소된 모임'
                            : upcoming
                            ? '✓ 참여 중'
                            : '끝난 모임',
                        color: upcoming
                            ? neighborhoodMint
                            : const Color(0xFFEDF1F4),
                        ink: upcoming ? PetColors.green : PetColors.secondary,
                      ),
                      if (m['is_host'] == true) const PetPill('모임장'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${m['title'] ?? ''}',
                    style: petText(18),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '◷ ${socialTime('${m['event_at']}')}${m['duration_minutes'] == null ? '' : ' · ${m['duration_minutes']}분'}',
                    style: petText(14, color: PetColors.secondary),
                  ),
                  Text(
                    '⌖ ${m['facility_name'] ?? '장소 확인 필요'}',
                    style: petText(14, color: PetColors.secondary),
                  ),
                  if (!cancelled) ...[
                    const Divider(height: 22),
                    Row(
                      children: [
                        for (final (i, person) in members.take(3).indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: NeighborAvatar(
                              person['is_me'] == true
                                  ? '나'
                                  : '${person['nickname'] ?? '이웃'}',
                              radius: 12,
                              color: [
                                PetColors.green,
                                const Color(0xFFEA77AA),
                                PetColors.purple,
                              ][i],
                            ),
                          ),
                        Text(
                          '${m['count'] ?? '—'}/${m['max_participants'] ?? '—'}명',
                          style: petText(14, color: PetColors.secondary),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.chevron_right,
                          color: PetColors.secondary,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() => ActivityCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        const Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: neighborhoodMint,
            child: Icon(Icons.people_outline, size: 42, color: PetColors.green),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          past ? '아직 지난 모임이 없어요' : '아직 참여한 모임이 없어요',
          style: petText(21),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '산책, 바둑, 노래… 가까운 모임에서\n이웃을 만나 보세요.',
          style: petText(16, color: PetColors.secondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ActivityButton(
          '동네 모임 둘러보기',
          color: PetColors.green,
          onTap: () => open(const MeetupPage()),
        ),
        const SizedBox(height: 8),
        ActivityButton(
          '+ 직접 모임 만들기',
          light: true,
          onTap: () => open(const NewMeetupPage()),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => NeighborhoodScreen(
    title: '참여한 모임',
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (c, s) {
        final rows = s.data;
        final loading = s.connectionState != ConnectionState.done;
        final upcoming = (rows ?? []).where(isUpcomingMeetup).toList()
          ..sort((a, b) => '${a['event_at']}'.compareTo('${b['event_at']}'));
        final previous =
            (rows ?? []).where((m) => !isUpcomingMeetup(m)).toList()..sort(
              (a, b) => '${b['event_at']}'.compareTo('${a['event_at']}'),
            );
        final selected = past ? previous : upcoming;
        final cancelled = selected
            .where((m) => m['participation_cancelled'] == true)
            .toList();
        final normal = selected
            .where((m) => m['participation_cancelled'] != true)
            .toList();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _tabs(loading || s.hasError ? null : rows),
              const SizedBox(height: 14),
              if (loading)
                const SizedBox(height: 320, child: NeighborhoodLoading())
              else if (s.hasError)
                ActivityEmpty(
                  '모임을 불러오지 못했어요',
                  message: '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
                  action: '다시 시도',
                  onAction: _refresh,
                )
              else if (selected.isEmpty)
                _empty()
              else ...[
                if (!past)
                  ActivityCard(
                    color: neighborhoodMint,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.people_outline,
                          color: PetColors.green,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '다음 모임은 ${meetupWhen(upcoming.first['event_at'] as String?)}이에요',
                            style: petText(16, color: PetColors.green),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!past)
                  NeighborhoodHeading('다가오는 모임', count: '${upcoming.length}개'),
                for (var i = 0; i < normal.length; i++) ...[
                  if (past &&
                      (i == 0 ||
                          _month(normal[i]['event_at']) !=
                              _month(normal[i - 1]['event_at'])))
                    NeighborhoodHeading(_month(normal[i]['event_at'])),
                  _row(normal[i]),
                ],
                if (cancelled.isNotEmpty) ...[
                  const NeighborhoodHeading('내가 취소한 모임'),
                  for (final m in cancelled) _row(m),
                ],
              ],
            ],
          ),
        );
      },
    ),
  );
  String _month(dynamic value) {
    final d = DateTime.tryParse('$value')?.toLocal();
    return d == null ? '지난 모임' : '${d.year}년 ${d.month}월';
  }
}

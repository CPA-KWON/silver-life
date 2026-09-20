import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';
import '../core/comment_count.dart';
import '../core/meetup_category.dart';
import '../core/region_scope.dart';
import 'new_meetup_page.dart';

class MeetupPage extends StatefulWidget {
  const MeetupPage({super.key});

  @override
  State<MeetupPage> createState() => _MeetupPageState();
}

class _MeetupPageState extends State<MeetupPage> {
  RegionScope _regionScope = RegionScope.sido;
  String? _mySido;
  String? _mySigungu;
  Future<List<Map<String, dynamic>>>? _meetupsFuture;

  @override
  void initState() {
    super.initState();
    _loadMyRegion();
  }

  Future<void> _loadMyRegion() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('region_sido, region_sigungu')
        .eq('id', userId)
        .single();
    if (mounted) {
      setState(() {
        _mySido = profile['region_sido'] as String;
        _mySigungu = profile['region_sigungu'] as String;
        _meetupsFuture = _fetchMeetups();
      });
    }
  }

  // Filtered by where the meetup actually is (facilities.region_*), not
  // where the poster lives — a meetup in 강남구 should show up under 강남구
  // regardless of who created it. `facilities!inner` also means a meetup
  // with no facility_id (shouldn't happen — the form requires one, and the
  // DB has a check constraint) never shows up here.
  Future<List<Map<String, dynamic>>> _fetchMeetups() async {
    var builder = Supabase.instance.client
        .from('posts')
        .select(
          'id, title, event_at, comments(count), '
          'facilities!inner(name, region_sido, region_sigungu), '
          'profiles(nickname)',
        )
        .eq('category', kMeetupCategory)
        .eq('facilities.region_sido', _mySido!);
    if (_regionScope == RegionScope.sigungu) {
      builder = builder.eq('facilities.region_sigungu', _mySigungu!);
    }
    final result = await builder.order('event_at', ascending: false);
    return List<Map<String, dynamic>>.from(result);
  }

  void _refresh() {
    if (_mySido == null) return;
    setState(() {
      _meetupsFuture = _fetchMeetups();
    });
  }

  void _setRegionScope(RegionScope scope) {
    setState(() {
      _regionScope = scope;
      _meetupsFuture = _fetchMeetups();
    });
  }

  String _formatEventAt(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}월 ${dt.day}일 (${weekdays[dt.weekday - 1]}) ${dt.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RegionScopeBar(
            scope: _regionScope,
            mySido: _mySido,
            mySigungu: _mySigungu,
            onChanged: _mySido == null ? null : _setRegionScope,
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _meetupsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
                }
                final all = snapshot.data ?? [];
                if (all.isEmpty) {
                  return const Center(
                    child: Text(
                      '모임이 없습니다.\n첫 모임을 만들어보세요.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final now = DateTime.now();
                final upcoming = all
                    .where((m) => DateTime.parse(m['event_at'] as String).toLocal().isAfter(now))
                    .toList()
                  ..sort(
                    (a, b) => (a['event_at'] as String).compareTo(b['event_at'] as String),
                  );
                final past = all
                    .where((m) => !DateTime.parse(m['event_at'] as String).toLocal().isAfter(now))
                    .toList();

                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (upcoming.isNotEmpty) ...[
                        Text('예정된 모임', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final meetup in upcoming) ...[
                          _MeetupCard(
                            meetup: meetup,
                            isPast: false,
                            formatEventAt: _formatEventAt,
                            onReturn: _refresh,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                      if (past.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('지난 모임', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        for (final meetup in past) ...[
                          _MeetupCard(
                            meetup: meetup,
                            isPast: true,
                            formatEventAt: _formatEventAt,
                            onReturn: _refresh,
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const NewMeetupPage()),
          );
          _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('모임 만들기'),
      ),
    );
  }
}

class _MeetupCard extends StatelessWidget {
  const _MeetupCard({
    required this.meetup,
    required this.isPast,
    required this.formatEventAt,
    required this.onReturn,
  });

  final Map<String, dynamic> meetup;
  final bool isPast;
  final String Function(String) formatEventAt;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final nickname = (meetup['profiles'] as Map?)?['nickname'] as String? ?? '알 수 없음';
    final facilityName = (meetup['facilities'] as Map?)?['name'] as String? ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PostDetailPage(postId: meetup['id'] as String)),
          );
          onReturn();
        },
        child: Opacity(
          opacity: isPast ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPast ? Icons.event_available : Icons.event,
                    color: scheme.secondary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meetup['title'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPast)
                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Chip(
                                label: Text('완료'),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(formatEventAt(meetup['event_at'] as String)),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$facilityName · $nickname',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          CommentCountBadge(commentCountOf(meetup)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

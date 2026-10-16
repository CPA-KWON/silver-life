import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';
import '../core/comment_count.dart';
import '../core/meetup_category.dart';
import '../app_theme.dart';
import '../core/region_scope.dart';
import '../ui/design_widgets.dart';
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
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? '오전' : '오후';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '$period $hour12:$minute';
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> items, bool isPast) {
    return SectionCard(
      header: SectionHeader(title: title),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            _MeetupCard(
              meetup: items[i],
              isPast: isPast,
              formatEventAt: _formatEventAt,
              onReturn: _refresh,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const PageTitle('모임'),
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '불러오지 못했습니다: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  );
                }
                final all = snapshot.data ?? [];
                if (all.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        '모임이 없습니다.\n첫 모임을 만들어보세요.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    children: [
                      if (upcoming.isNotEmpty)
                        _buildSection('다가오는 모임', upcoming, false),
                      if (upcoming.isNotEmpty && past.isNotEmpty)
                        const SizedBox(height: 24),
                      if (past.isNotEmpty) _buildSection('지난 모임', past, true),
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
    final facilityName = (meetup['facilities'] as Map?)?['name'] as String? ?? '';
    final textTheme = Theme.of(context).textTheme;
    final eventAt = meetup['event_at'] as String;
    final meta = facilityName.isEmpty
        ? formatEventAt(eventAt)
        : '${formatEventAt(eventAt)} · $facilityName';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PostDetailPage(postId: meetup['id'] as String)),
        );
        onReturn();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            DateBlock(
              date: DateTime.parse(eventAt).toLocal(),
              size: DateBlockSize.compact,
              muted: isPast,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meetup['title'] as String,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isPast ? AppColors.scheduleText : AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    style: textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(
                        label: isPast ? '완료' : '예정',
                        tone: isPast ? StatusPillTone.neutral : StatusPillTone.success,
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
    );
  }
}

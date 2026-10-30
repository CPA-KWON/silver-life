import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../activity/activity_widgets.dart' show ActivityInfo;
import '../attendance/point_badge.dart';
import '../core/comment_count.dart';
import '../core/region_scope.dart';
import '../core/neighborhood_region.dart';
import '../core/time_ago.dart';
import '../core/meetup_category.dart';
import '../community/post_detail_page.dart';
import '../community/new_post_page.dart';
import '../meetup/new_meetup_page.dart';
import '../profile/my_post_list_page.dart';
import 'neighborhood_repository.dart';

const meetupTopics = ['산책·운동', '바둑·장기', '노래·취미', '배움', '봉사'];
const communityCategories = ['자유게시판', '건강정보', '나눔·도움요청', '질문'];
String socialCategory(String v) => v == '나눔·도움요청' ? '나눔' : v;
String socialTime(String value) {
  final d = DateTime.tryParse(value)?.toLocal();
  if (d == null) return '시간 확인 필요';
  return '${d.hour < 12 ? '오전' : '오후'} ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')}';
}

bool meetupEnded(SocialData p) =>
    p['meetup_cancelled'] == true ||
    (DateTime.tryParse('${p['event_at']}')
            ?.add(
              Duration(minutes: (p['duration_minutes'] as num? ?? 60).toInt()),
            )
            .isBefore(DateTime.now()) ??
        false);

class NeighborhoodFeed extends StatefulWidget {
  const NeighborhoodFeed({super.key, required this.meetup, this.active = true});
  final bool active;
  final bool meetup;
  @override
  State<NeighborhoodFeed> createState() => _FeedState();
}

class _FeedState extends State<NeighborhoodFeed> {
  RegionScope scope = RegionScope.sigungu;
  String? sido = defaultNeighborhood.sido,
      sigungu = defaultNeighborhood.sigungu,
      category;
  late Future<List<SocialData>> data = load();
  bool extras = true;
  bool _extrasLoading = false;
  DateTime? _loadedAt;
  List<SocialData>? _lastData;
  bool _preserveResults = false;
  int _request = 0;
  bool _loading = false;

  @override
  void didUpdateWidget(NeighborhoodFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active &&
        !oldWidget.active &&
        !_loading &&
        (_loadedAt == null ||
            DateTime.now().difference(_loadedAt!) >
                const Duration(seconds: 30))) {
      refresh();
    }
  }

  Future<List<SocialData>> load() async {
    final request = ++_request;
    _loading = true;
    final requestedScope = scope, requestedCategory = category;
    try {
      final c = Supabase.instance.client;
      final neighborhood = await NeighborhoodRegionResolver.shared.resolve();
      sido = neighborhood.sido;
      sigungu = neighborhood.sigungu;
      var q = c
          .from('posts')
          .select(
            widget.meetup
                ? '*,comments(count),facilities!inner(id,name,address,lat,lng,region_sido,region_sigungu),profiles(nickname,region_sigungu)'
                : '*,comments(count),profiles!inner(nickname,region_sido,region_sigungu)',
          );
      q = widget.meetup
          ? q.eq('category', kMeetupCategory)
          : q.neq('category', kMeetupCategory);
      final region = widget.meetup ? 'facilities' : 'profiles';
      q = q.eq('$region.region_sido', sido!);
      if (requestedScope == RegionScope.sigungu) {
        q = q.eq('$region.region_sigungu', sigungu!);
      }
      if (requestedCategory != null) {
        q = q.eq(
          widget.meetup ? 'meetup_topic' : 'category',
          requestedCategory,
        );
      }
      final list = List<SocialData>.from(
        await q
            .order(
              widget.meetup ? 'event_at' : 'created_at',
              ascending: widget.meetup,
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (request == _request) {
        _extrasLoading = list.isNotEmpty;
        extras = true;
        _lastData = list;
        _loadedAt = DateTime.now();
      }
      unawaited(_enrich(list, request));
      return list;
    } finally {
      if (request == _request) _loading = false;
    }
  }

  Future<void> _enrich(List<SocialData> rows, int request) async {
    var complete = false;
    try {
      complete = await NeighborhoodRepository()
          .enrich(rows)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // The public list remains usable when supplementary counts are offline.
    }
    if (mounted && request == _request) {
      setState(() {
        extras = complete;
        _extrasLoading = false;
      });
    }
  }

  Future<void> refresh({bool preserveResults = true}) async {
    _preserveResults = preserveResults;
    final f = load();
    setState(() {
      data = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) await refresh();
  }

  Future<void> compose() async {
    if (widget.meetup) {
      await open(const NewMeetupPage());
      return;
    }
    String? created;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NewPostPage(onCreated: (id) => created = id),
      ),
    );
    if (!mounted) return;
    // A visitor's GPS district may differ from the author's registered region.
    // Always show the saved post, even if it is outside the current feed filter.
    if (created != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PostDetailPage(postId: created!)),
      );
    }
    if (mounted) await refresh();
  }

  void rules() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('커뮤니티 이용 규칙'),
      content: const Text(
        '이웃을 존중하는 말을 사용해 주세요. 욕설·비방, 광고, 사기성 글과 개인정보 공개는 삼가 주세요. 신고가 누적된 글과 댓글은 기존 운영 기준에 따라 숨겨집니다.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인')),
      ],
    ),
  );
  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: widget.meetup ? '동네 모임' : '커뮤니티',
    back: false,
    subtitle: widget.meetup ? '이웃과 함께하는 동네 모임' : '우리 동네 이웃들의 이야기',
    tint: widget.meetup ? neighborhoodMint : neighborhoodLavender,
    actions: widget.meetup
        ? [
            TextButton.icon(
              onPressed: () =>
                  open(const MyPostListPage(title: '내가 만든 모임', isMeetup: true)),
              icon: const Icon(Icons.people_outline),
              label: const Text('내 모임'),
            ),
            const _Wallet(),
          ]
        : const [],
    floating: FloatingActionButton.extended(
      onPressed: compose,
      icon: Icon(widget.meetup ? Icons.add : Icons.edit_outlined),
      label: Text(widget.meetup ? '모임 만들기' : '글쓰기'),
    ),
    child: FutureBuilder<List<SocialData>>(
      future: data,
      builder: (c, s) {
        final rows =
            s.connectionState == ConnectionState.waiting && !_preserveResults
            ? null
            : s.data ?? (_preserveResults ? _lastData : null);
        return Column(
          children: [
            RegionScopeBar(
              scope: scope,
              mySido: sido,
              mySigungu: sigungu,
              onChanged: sido == null
                  ? null
                  : (v) {
                      scope = v;
                      refresh(preserveResults: false);
                    },
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  for (final v in [
                    '전체',
                    ...(widget.meetup ? meetupTopics : communityCategories),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(
                          socialCategory(v),
                          style: petText(
                            16,
                            color: (category ?? '전체') == v
                                ? Colors.white
                                : PetColors.ink,
                          ),
                        ),
                        selected: (category ?? '전체') == v,
                        showCheckmark: false,
                        selectedColor: PetColors.blue,
                        backgroundColor: Colors.white,
                        onSelected: (_) {
                          category = v == '전체' ? null : v;
                          refresh(preserveResults: false);
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: rows == null && s.connectionState != ConnectionState.done
                  ? const NeighborhoodLoading()
                  : rows == null && s.hasError
                  ? ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        ActivityEmpty(
                          widget.meetup ? '모임을 불러오지 못했어요' : '글을 불러오지 못했어요',
                          message: '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
                          icon: Icons.wifi_off_rounded,
                          action: '다시 시도',
                          onAction: refresh,
                        ),
                      ],
                    )
                  : RefreshIndicator(
                      onRefresh: refresh,
                      child: _feedList(
                        rows ?? const [],
                        refreshFailed: s.hasError,
                      ),
                    ),
            ),
          ],
        );
      },
    ),
  );
  Widget _feedList(List<SocialData> rows, {bool refreshFailed = false}) {
    final upcoming = widget.meetup
        ? rows.where((p) => !meetupEnded(p)).toList()
        : <SocialData>[];
    final past = widget.meetup
        ? rows.where(meetupEnded).toList()
        : <SocialData>[];
    // Build only visible cards; long feeds no longer construct every card at once.
    final entries = <Widget Function()>[
      if (!widget.meetup)
        () => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ActivityCard(
            onTap: rules,
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: PetColors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('커뮤니티 이용 규칙', style: petText(18)),
                      Text(
                        '욕설·광고·사기 글은 신고하면 숨겨져요',
                        style: petText(14, color: PetColors.secondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: PetColors.purple),
              ],
            ),
          ),
        ),
      if (rows.isEmpty)
        () => ActivityEmpty(
          widget.meetup ? '우리 동네에 아직 모임이 없어요' : '우리 동네에 아직 글이 없어요',
          message: widget.meetup
              ? '가까운 이웃과 함께할 첫 모임을 만들어 보세요.'
              : '오늘 있었던 일, 궁금한 점을 편하게 남겨 주세요.',
          icon: widget.meetup ? Icons.groups_outlined : Icons.edit_outlined,
          action: widget.meetup ? '모임 만들기' : '첫 글 쓰기',
          onAction: compose,
          secondary: '${sido ?? '시/도'} 전체 보기',
          onSecondary: () {
            scope = RegionScope.sido;
            category = null;
            refresh(preserveResults: false);
          },
        ),
      if (widget.meetup) ...[
        for (final group in [(upcoming, false), (past, true)])
          if (group.$1.isNotEmpty) ...[
            () => NeighborhoodHeading(
              group.$2 ? '지난 모임' : '다가오는 모임',
              count: '${group.$1.length}개',
            ),
            for (final p in group.$1) () => meetupCard(p),
          ],
      ] else
        for (final p in rows) () => postCard(p),
      if (refreshFailed)
        () => ActivityInfo('새 소식을 갱신하지 못했어요. 다시 시도해 주세요.', onRetry: refresh),
      if (_extrasLoading)
        () => Text(
          '참여·공감 현황을 확인하고 있어요.',
          style: petText(14, color: PetColors.secondary),
        ),
      if (!extras && rows.isNotEmpty)
        () => Text(
          '참여·공감 현황을 확인할 수 없어요. 잠시 후 새로고침해 주세요.',
          style: petText(14, color: PetColors.secondary),
        ),
    ];
    return ListView.builder(
      key: PageStorageKey(widget.meetup ? 'meetup-feed' : 'community-feed'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: entries.length,
      itemBuilder: (_, index) => entries[index](),
    );
  }

  Widget meetupCard(SocialData p) {
    final d = DateTime.tryParse('${p['event_at']}')?.toLocal();
    final ended = meetupEnded(p);
    final count = p['member_count'] as num?,
        capacity = p['max_participants'] as num?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ActivityCard(
        onTap: () => open(PostDetailPage(postId: p['id'])),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 68,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: ended
                    ? const Color(0xFFEDF2F6)
                    : const Color(0xFFD2EFDF),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: [
                  Text(
                    '${d?.month ?? ''}월',
                    style: petText(14, color: PetColors.green),
                  ),
                  Text(
                    '${d?.day ?? '—'}',
                    style: petText(
                      30,
                      color: PetColors.green,
                      weight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    d == null
                        ? ''
                        : ['월', '화', '수', '목', '금', '토', '일'][d.weekday - 1],
                    style: petText(14, color: PetColors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      PetPill(
                        '${p['meetup_topic'] ?? '동네 모임'}',
                        color: PetColors.mint,
                        ink: PetColors.green,
                        fontSize: 12,
                      ),
                      PetPill(
                        p['meetup_cancelled'] == true
                            ? '취소됨'
                            : ended
                            ? '지난 모임'
                            : p['joined'] == true
                            ? '✓ 참여 중'
                            : count != null &&
                                  capacity != null &&
                                  capacity - count <= 2
                            ? '${(capacity - count).clamp(0, 100)}자리 남음'
                            : '모집 중',
                        fontSize: 12,
                        color: ended
                            ? const Color(0xFFEDF2F6)
                            : PetColors.yellow,
                        ink: PetColors.green,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${p['title']}',
                    style: petText(21, weight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${socialTime('${p['event_at']}')} · ${(p['duration_minutes'] as num? ?? 60)}분',
                    style: petText(16, color: PetColors.secondary),
                  ),
                  Text(
                    '${p['facilities']?['name'] ?? ''}',
                    style: petText(16, color: PetColors.secondary),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1),
                  ),
                  Row(
                    children: [
                      if (p['participants'] is List)
                        for (final r in (p['participants'] as List).take(3))
                          NeighborAvatar('${r['nickname']}', radius: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          count == null
                              ? '참여 현황 확인 필요'
                              : '$count/${capacity ?? '—'}명',
                          style: petText(16),
                        ),
                      ),
                      const Icon(Icons.chevron_right),
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

  Widget postCard(SocialData p) {
    final author = p['profiles'] as Map? ?? {};
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ActivityCard(
        onTap: () => open(PostDetailPage(postId: p['id'])),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                NeighborAvatar('${author['nickname'] ?? '이웃'}'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${author['nickname'] ?? '이웃'}', style: petText(18)),
                      Text(
                        '${author['region_sigungu'] ?? ''} · ${timeAgo(DateTime.tryParse('${p['created_at']}')?.toLocal() ?? DateTime.now())}',
                        style: petText(13, color: PetColors.secondary),
                      ),
                    ],
                  ),
                ),
                PetPill(
                  socialCategory('${p['category']}'),
                  fontSize: 12,
                  color: PetColors.mint,
                  ink: PetColors.blue,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('${p['title']}', style: petText(22, weight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              '${p['content'] ?? ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: petText(17, color: PetColors.secondary),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            Wrap(
              spacing: 18,
              children: [
                Text(
                  '▱ 댓글 ${commentCountOf(p)}',
                  style: petText(14, color: PetColors.secondary),
                ),
                if (p['likes'] is num)
                  Text(
                    '♡ 공감 ${p['likes']}',
                    style: petText(14, color: PetColors.pink),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Wallet extends StatelessWidget {
  const _Wallet();
  @override
  Widget build(BuildContext c) =>
      const SizedBox(width: 100, child: PointBadge());
}

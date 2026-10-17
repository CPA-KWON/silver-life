import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/phone_call.dart';
import '../activity/activity_widgets.dart';

import '../app_theme.dart';
import '../community/post_detail_page.dart';
import '../core/comment_count.dart';
import '../core/meetup_category.dart';
import '../facility/facility_search_page.dart';
import '../core/time_ago.dart';
import '../facility/naver_local_search.dart';
import '../meetup/new_meetup_page.dart';
import '../ui/design_widgets.dart';
import 'nearby_facilities.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, this.onNavigate, this.nearbyLoader});

  final ValueChanged<int>? onNavigate;
  final NearbyLoader? nearbyLoader;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<_HomeData> _dataFuture;
  int _nearbyVersion = 0;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadHomeData();
  }

  Future<_HomeData> _loadHomeData() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser!.id;

    final profile = await client
        .from('profiles')
        .select('nickname, region_sido, region_sigungu')
        .eq('id', userId)
        .single();

    final failed = <String>[];
    Future<List<Map<String, dynamic>>> guarded(
      String name,
      Future<List<Map<String, dynamic>>> Function() fetch,
    ) async {
      try {
        return await fetch();
      } catch (_) {
        failed.add(name);
        return [];
      }
    }

    final recentPosts = await guarded(
      '최근 커뮤니티 글',
      () async => List<Map<String, dynamic>>.from(
        await client
            .from('posts')
            .select(
              'id, title, category, created_at, comments(count), profiles(nickname)',
            )
            .neq('category', kMeetupCategory)
            .order('created_at', ascending: false)
            .limit(3),
      ),
    );
    final upcomingMeetups = await guarded(
      '다가오는 모임',
      () async => List<Map<String, dynamic>>.from(
        await client
            .from('posts')
            .select(
              'id, title, event_at, facilities!inner(name, region_sido, region_sigungu)',
            )
            .eq('category', kMeetupCategory)
            .eq('facilities.region_sido', profile['region_sido'] as String)
            .eq(
              'facilities.region_sigungu',
              profile['region_sigungu'] as String,
            )
            .gte('event_at', DateTime.now().toUtc().toIso8601String())
            .order('event_at')
            .limit(2),
      ),
    );
    final favorites = await guarded(
      '즐겨찾는 시설',
      () async => List<Map<String, dynamic>>.from(
        await client
            .from('favorites')
            .select('id, name, address, telephone, lat, lng, category')
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(3),
      ),
    );

    return _HomeData(
      nickname: profile['nickname'] as String,
      failedSections: failed,
      recentPosts: List<Map<String, dynamic>>.from(recentPosts),
      upcomingMeetups: List<Map<String, dynamic>>.from(upcomingMeetups),
      favorites: List<Map<String, dynamic>>.from(favorites),
    );
  }

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String get _todayLabel {
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일 ${_weekdays[now.weekday - 1]}요일';
  }

  String _clock(DateTime dt) {
    final h = dt.hour;
    final period = h < 12 ? '오전' : '오후';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$period $h12:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _facilityName(Map<String, dynamic> meetup) =>
      (meetup['facilities'] as Map?)?['name'] as String? ?? '';

  Future<void> _refreshHome() async {
    if (!mounted) return;
    final f = _loadHomeData();
    setState(() {
      _dataFuture = f;
      _nearbyVersion++;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> _openPost(String id) async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PostDetailPage(postId: id)));
    if (mounted) await _refreshHome();
  }

  Future<void> _openFacility(FacilityResult r) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('시설찾기')),
          body: FacilitySearchPage(initialFacility: r),
        ),
      ),
    );
    if (mounted) await _refreshHome();
  }

  Future<void> _createMeetup() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NewMeetupPage()));
    if (!mounted) return;
    await _refreshHome();
  }

  static TagTone _toneFor(String category) => switch (category) {
    '자유게시판' => TagTone.lavender,
    '건강정보' => TagTone.mint,
    '나눔·도움요청' => TagTone.blue,
    _ => TagTone.neutral,
  };

  IconData _facilityIcon(String category) {
    if (category.contains('약국')) return Icons.local_pharmacy;
    if (category.contains('병원') || category.contains('의원')) {
      return Icons.local_hospital;
    }
    if (category.contains('경로당') || category.contains('복지')) {
      return Icons.home_work;
    }
    return Icons.place;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshHome,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          FutureBuilder<_HomeData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _buildError(context, snapshot.error);
              }
              return _buildTop(context, snapshot.data!);
            },
          ),
          const SizedBox(height: 24),
          _buildQuickActions(context),
          const SizedBox(height: 24),
          const ActivityHomeSection(),
          const SizedBox(height: 24),
          NearbyFacilitiesSection(
            key: const ValueKey('home-nearby'),
            loader: widget.nearbyLoader,
            refreshVersion: _nearbyVersion,
            onOpenFacility: _openFacility,
            onShowMap: () => widget.onNavigate?.call(1),
          ),
          FutureBuilder<_HomeData>(
            future: _dataFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (snapshot.connectionState != ConnectionState.done ||
                  snapshot.hasError ||
                  data == null) {
                return const SizedBox.shrink();
              }
              return _buildBottom(context, data);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, Object? error) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            '불러오지 못했습니다: $error',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          TextButton(onPressed: _refreshHome, child: const Text('다시 시도')),
        ],
      ),
    );
  }

  Widget _buildTop(BuildContext context, _HomeData data) {
    final textTheme = Theme.of(context).textTheme;
    final meetups = data.upcomingMeetups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_todayLabel, style: textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: data.nickname,
                style: const TextStyle(color: AppColors.primary),
              ),
              const TextSpan(text: '님, 안녕하세요'),
            ],
          ),
          style: textTheme.titleLarge,
        ),
        if (data.failedSections.isNotEmpty)
          TextButton(
            onPressed: _refreshHome,
            child: Text('${data.failedSections.join(', ')} 조회 실패 · 다시 시도'),
          ),
        if (meetups.isEmpty && !data.failedSections.contains('다가오는 모임')) ...[
          const SizedBox(height: 16),
          const SectionCard(
            header: SectionHeader(title: '다가오는 모임'),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('아직 예정된 모임이 없어요.'),
            ),
          ),
        ],
        if (meetups.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildHeroMeetup(context, meetups.first),
          if (meetups.length > 1) ...[
            const SizedBox(height: 8),
            _buildCompactMeetup(context, meetups[1]),
          ],
        ],
      ],
    );
  }

  Widget _buildHeroMeetup(BuildContext context, Map<String, dynamic> meetup) {
    final textTheme = Theme.of(context).textTheme;
    final dt = DateTime.parse(meetup['event_at'] as String).toLocal();
    final place = _facilityName(meetup);
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
        ),
        child: InkWell(
          onTap: () => _openPost(meetup['id'] as String),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '다가오는 모임',
                        style: textTheme.labelMedium?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const StatusPill(label: '예정', tone: StatusPillTone.success),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DateBlock(date: dt),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meetup['title'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(
                                Icons.schedule,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _clock(dt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: AppColors.scheduleText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (place.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.place_outlined,
                                    size: 16,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    place,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: AppColors.scheduleText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactMeetup(
    BuildContext context,
    Map<String, dynamic> meetup,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final dt = DateTime.parse(meetup['event_at'] as String).toLocal();
    final place = _facilityName(meetup);
    final meta = [
      '${_weekdays[dt.weekday - 1]} ${_clock(dt)}',
      if (place.isNotEmpty) place,
    ].join(' · ');
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPost(meetup['id'] as String),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${dt.month}월',
                      style: textTheme.labelSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      '${dt.day}',
                      style: textTheme.titleMedium?.copyWith(fontSize: 20),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meetup['title'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    // IntrinsicHeight gives the stretched Row a finite height inside the
    // ListView, so both tiles match the taller one (e.g. at large text).
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _QuickTile(
              icon: Icons.search,
              title: '시설 찾기',
              sub: '병원 · 약국 · 경로당',
              primary: true,
              onTap: () => widget.onNavigate?.call(1),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickTile(
              icon: Icons.group_add_outlined,
              title: '모임 만들기',
              sub: '함께할 이웃 모으기',
              primary: false,
              onTap: _createMeetup,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(BuildContext context, _HomeData data) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.failedSections.contains('즐겨찾는 시설')) ...[
          const SizedBox(height: 24),
          SectionCard(
            header: const SectionHeader(title: '즐겨찾는 시설'),
            child: TextButton(
              onPressed: _refreshHome,
              child: const Text('시설을 불러오지 못했어요. 다시 시도'),
            ),
          ),
        ] else ...[
          const SizedBox(height: 24),
          SectionCard(
            header: const SectionHeader(title: '즐겨찾는 시설'),
            child: Column(
              children: [
                if (data.favorites.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('아직 즐겨찾는 시설이 없어요.'),
                  ),
                for (final facility in data.favorites)
                  _buildFavoriteRow(context, facility),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        SectionCard(
          header: SectionHeader(
            title: '최근 커뮤니티 글',
            trailing: TextButton(
              onPressed: () => widget.onNavigate?.call(3),
              child: const Text('전체 보기'),
            ),
          ),
          child: data.failedSections.contains('최근 커뮤니티 글')
              ? TextButton(
                  onPressed: _refreshHome,
                  child: const Text('게시글을 불러오지 못했어요. 다시 시도'),
                )
              : data.recentPosts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('아직 게시글이 없습니다.', style: textTheme.bodyMedium),
                )
              : Column(
                  children: [
                    for (final post in data.recentPosts)
                      _buildPostRow(context, post),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildFavoriteRow(BuildContext context, Map<String, dynamic> f) {
    final textTheme = Theme.of(context).textTheme;
    final category = f['category'] as String? ?? '';
    final address = f['address'] as String? ?? '';
    final tel = f['telephone'] as String? ?? '';
    final sub = [
      if (category.isNotEmpty) category,
      if (address.isNotEmpty) address,
    ].join(' · ');
    return InkWell(
      onTap: () => _openFacility(
        FacilityResult(
          name: f['name'] as String,
          category: category,
          address: address,
          telephone: tel,
          lat: (f['lat'] as num).toDouble(),
          lng: (f['lng'] as num).toDouble(),
          distanceMeters: 0,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              IconBadge(
                icon: _facilityIcon(category),
                background: AppColors.blueTint,
                color: AppColors.blueText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f['name'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall,
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (tel.isNotEmpty)
                Tooltip(
                  message: '전화 걸기',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => callFacility(context, tel),
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Center(
                        child: IconBadge(icon: Icons.call, size: 40),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostRow(BuildContext context, Map<String, dynamic> post) {
    final textTheme = Theme.of(context).textTheme;
    final category = post['category'] as String? ?? '';
    final nickname = (post['profiles'] as Map?)?['nickname'] as String?;
    final createdRaw = post['created_at'] as String?;
    final created = createdRaw == null
        ? null
        : DateTime.tryParse(createdRaw)?.toLocal();
    final comments = commentCountOf(post);
    final meta = [
      if (nickname != null && nickname.isNotEmpty) nickname,
      if (created != null) timeAgo(created),
      if (comments > 0) '댓글 $comments',
    ].join(' · ');
    return InkWell(
      onTap: () => _openPost(post['id'] as String),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 56,
          minWidth: double.infinity,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (category.isNotEmpty) ...[
                TagBadge(label: category, tone: _toneFor(category)),
                const SizedBox(height: 8),
              ],
              Text(
                post['title'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall,
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.title,
    required this.sub,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fg = primary ? Colors.white : AppColors.primary;
    return Material(
      color: primary ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(color: fg),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: primary
                              ? const Color(0xFFE0E3FF)
                              : AppColors.textSecondary,
                        ),
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

class _HomeData {
  const _HomeData({
    required this.nickname,
    required this.recentPosts,
    required this.upcomingMeetups,
    required this.favorites,
    this.failedSections = const [],
  });

  final List<String> failedSections;
  final String nickname;
  final List<Map<String, dynamic>> recentPosts;
  final List<Map<String, dynamic>> upcomingMeetups;
  final List<Map<String, dynamic>> favorites;
}

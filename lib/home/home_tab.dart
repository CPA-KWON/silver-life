import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../community/post_detail_page.dart';
import '../core/meetup_category.dart';
import '../facility/facility_search_page.dart';
import '../facility/naver_local_search.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<_HomeData> _dataFuture;

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

    final recentPosts = await client
        .from('posts')
        .select('id, title, category')
        .neq('category', kMeetupCategory)
        .order('created_at', ascending: false)
        .limit(3);

    // Home only ever shows the tightest scope (own 시/군/구) — the Meetup
    // tab has the 전체/시도/시군구 toggle for anything broader. Filtered by
    // where the meetup actually is (facilities.region_*), not where the
    // poster lives.
    final upcomingMeetups = await client
        .from('posts')
        .select(
          'id, title, event_at, facilities!inner(name, region_sido, region_sigungu)',
        )
        .eq('category', kMeetupCategory)
        .eq('facilities.region_sido', profile['region_sido'] as String)
        .eq('facilities.region_sigungu', profile['region_sigungu'] as String)
        .gte('event_at', DateTime.now().toUtc().toIso8601String())
        .order('event_at')
        .limit(2);

    final favorites = await client
        .from('favorites')
        .select('id, name, address, telephone, lat, lng, category')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(3);

    return _HomeData(
      nickname: profile['nickname'] as String,
      recentPosts: List<Map<String, dynamic>>.from(recentPosts),
      upcomingMeetups: List<Map<String, dynamic>>.from(upcomingMeetups),
      favorites: List<Map<String, dynamic>>.from(favorites),
    );
  }

  String _formatEventAt(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}.${dt.day} ${dt.hour}:$minute';
  }

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String get _todayLabel {
    final now = DateTime.now();
    return '${now.year}년 ${now.month}월 ${now.day}일 (${_weekdays[now.weekday - 1]})';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<_HomeData>(
      future: _dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
        }

        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${data.nickname}님, 안녕하세요', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(_todayLabel, style: textTheme.bodyMedium),
            if (data.upcomingMeetups.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('다가오는 모임', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final meetup in data.upcomingMeetups)
                Card(
                  color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.08),
                  child: ListTile(
                    leading: Icon(Icons.event, color: Theme.of(context).colorScheme.secondary),
                    title: Text(
                      meetup['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${_formatEventAt(meetup['event_at'] as String)} · '
                      '${(meetup['facilities'] as Map?)?['name'] as String? ?? ''}',
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailPage(postId: meetup['id'] as String),
                      ),
                    ),
                  ),
                ),
            ],
            if (data.favorites.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('즐겨찾는 시설', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              for (final facility in data.favorites)
                Card(
                  child: ListTile(
                    title: Text(
                      facility['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: (facility['telephone'] as String?)?.isNotEmpty == true
                        ? IconButton(
                            icon: const Icon(Icons.call),
                            tooltip: '전화 걸기',
                            onPressed: () =>
                                launchUrl(Uri.parse('tel:${facility['telephone']}')),
                          )
                        : null,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('시설찾기')),
                          body: FacilitySearchPage(
                            initialFacility: FacilityResult(
                              name: facility['name'] as String,
                              category: facility['category'] as String? ?? '',
                              address: facility['address'] as String? ?? '',
                              telephone: facility['telephone'] as String? ?? '',
                              lat: (facility['lat'] as num).toDouble(),
                              lng: (facility['lng'] as num).toDouble(),
                              distanceMeters: 0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            Text('최근 커뮤니티 글', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            if (data.recentPosts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('아직 게시글이 없습니다.'),
              )
            else
              for (final post in data.recentPosts)
                Card(
                  child: ListTile(
                    title: Text(
                      post['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('[${post['category']}]'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailPage(postId: post['id'] as String),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.nickname,
    required this.recentPosts,
    required this.upcomingMeetups,
    required this.favorites,
  });

  final String nickname;
  final List<Map<String, dynamic>> recentPosts;
  final List<Map<String, dynamic>> upcomingMeetups;
  final List<Map<String, dynamic>> favorites;
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';

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
        .select('nickname')
        .eq('id', userId)
        .single();

    final recentPosts = await client
        .from('posts')
        .select('id, title, category')
        .order('created_at', ascending: false)
        .limit(3);

    return _HomeData(
      nickname: profile['nickname'] as String,
      recentPosts: List<Map<String, dynamic>>.from(recentPosts),
    );
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
  const _HomeData({required this.nickname, required this.recentPosts});

  final String nickname;
  final List<Map<String, dynamic>> recentPosts;
}

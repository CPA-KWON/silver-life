import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';
import '../core/comment_count.dart';
import '../core/meetup_category.dart';

/// Shared by "내 게시글 관리" and "내 모임 관리": both just list the current
/// user's own posts, split by whether the category is the meetup one.
class MyPostListPage extends StatefulWidget {
  const MyPostListPage({super.key, required this.title, required this.isMeetup});

  final String title;
  final bool isMeetup;

  @override
  State<MyPostListPage> createState() => _MyPostListPageState();
}

class _MyPostListPageState extends State<MyPostListPage> {
  late Future<List<Map<String, dynamic>>> _postsFuture;

  @override
  void initState() {
    super.initState();
    _postsFuture = _loadPosts();
  }

  Future<List<Map<String, dynamic>>> _loadPosts() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    var builder = Supabase.instance.client
        .from('posts')
        .select('id, title, category, created_at, comments(count)')
        .eq('author_id', userId);
    builder = widget.isMeetup
        ? builder.eq('category', kMeetupCategory)
        : builder.neq('category', kMeetupCategory);
    final result = await builder.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(result);
  }

  void _refresh() {
    setState(() => _postsFuture = _loadPosts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _postsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
          }
          final posts = snapshot.data ?? [];
          if (posts.isEmpty) {
            return const Center(child: Text('작성한 글이 없습니다.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: posts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final post = posts[i];
                return Card(
                  child: ListTile(
                    title: Text(
                      post['title'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('[${post['category']}]'),
                    trailing: CommentCountBadge(commentCountOf(post)),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PostDetailPage(postId: post['id'] as String),
                        ),
                      );
                      _refresh();
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

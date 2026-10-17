import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';
import '../core/comment_count.dart';
import '../core/meetup_category.dart';
import '../core/time_ago.dart';
import '../ui/design_widgets.dart';

/// Shared by "내 게시글 관리" and "내 모임 관리": both just list the current
/// user's own posts, split by whether the category is the meetup one.
class MyPostListPage extends StatefulWidget {
  const MyPostListPage({
    super.key,
    required this.title,
    required this.isMeetup,
  });

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

  static TagTone _toneFor(String category) => switch (category) {
    '자유게시판' => TagTone.lavender,
    '건강정보' => TagTone.mint,
    '나눔·도움요청' => TagTone.blue,
    _ => TagTone.neutral,
  };

  Widget _buildRow(Map<String, dynamic> post) {
    final category = post['category'] as String? ?? '';
    final created = DateTime.tryParse(post['created_at'] as String? ?? '');
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PostDetailPage(postId: post['id'] as String),
          ),
        );
        _refresh();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TagBadge(label: category, tone: _toneFor(category)),
            const SizedBox(height: 8),
            Text(
              post['title'] as String,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (created != null)
                  Text(timeAgo(created.toLocal()), style: textTheme.bodySmall),
                CommentCountBadge(commentCountOf(post)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _postsFuture = _loadPosts();
    });
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
            return _message('불러오지 못했습니다: ${snapshot.error}');
          }
          final posts = snapshot.data ?? [];
          if (posts.isEmpty) {
            return _message('작성한 글이 없습니다.');
          }
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < posts.length; i++) ...[
                        _buildRow(posts[i]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/meetup_category.dart';
import '../meetup/new_meetup_page.dart';
import 'new_post_page.dart';

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late Future<Map<String, dynamic>> _postFuture;
  late Future<List<Map<String, dynamic>>> _commentsFuture;
  final _commentController = TextEditingController();
  bool _isPostingComment = false;

  @override
  void initState() {
    super.initState();
    _postFuture = _fetchPost();
    _commentsFuture = _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetchPost() {
    return Supabase.instance.client
        .from('posts')
        .select(
          'id, title, content, category, created_at, event_at, author_id, '
          'facilities(id, name, address, lat, lng, category, telephone), '
          'profiles(nickname)',
        )
        .eq('id', widget.postId)
        .single();
  }

  Future<void> _editPost(Map<String, dynamic> post) async {
    final isMeetup = post['category'] == kMeetupCategory;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => isMeetup
            ? NewMeetupPage(
                existingPost: {
                  'id': post['id'],
                  'title': post['title'],
                  'content': post['content'],
                  'event_at': post['event_at'],
                  'facility': post['facilities'],
                },
              )
            : NewPostPage(
                existingPost: {
                  'id': post['id'],
                  'category': post['category'],
                  'title': post['title'],
                  'content': post['content'],
                },
              ),
      ),
    );
    if (changed == true && mounted) {
      setState(() {
        _postFuture = _fetchPost();
      });
    }
  }

  Future<void> _deletePost() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('삭제하시겠어요?'),
        content: const Text('삭제한 글은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('posts').delete().eq('id', widget.postId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('삭제에 실패했습니다: $e')));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchComments() async {
    final result = await Supabase.instance.client
        .from('comments')
        .select('id, content, created_at, profiles(nickname)')
        .eq('post_id', widget.postId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(result);
  }

  void _refreshComments() {
    // Block body, not arrow: an arrow body's value would be the Future
    // that _fetchComments() returns, and setState() rejects a callback
    // that returns a Future instead of void.
    setState(() {
      _commentsFuture = _fetchComments();
    });
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPostingComment = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('comments').insert({
        'post_id': widget.postId,
        'author_id': userId,
        'content': text,
      });
      _commentController.clear();
      _refreshComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('댓글 등록에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  String _nicknameOf(Map<String, dynamic> row) =>
      (row['profiles'] as Map?)?['nickname'] as String? ?? '알 수 없음';

  String _formatEventAt(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}.${dt.month}.${dt.day} ${dt.hour}:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('게시글'),
        actions: [
          FutureBuilder<Map<String, dynamic>>(
            future: _postFuture,
            builder: (context, snapshot) {
              final post = snapshot.data;
              if (post == null) return const SizedBox.shrink();
              final isAuthor =
                  post['author_id'] == Supabase.instance.client.auth.currentUser!.id;
              if (!isAuthor) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _editPost(post);
                  if (value == 'delete') _deletePost();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('수정')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FutureBuilder<Map<String, dynamic>>(
                  future: _postFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Text('불러오지 못했습니다: ${snapshot.error}');
                    }
                    final post = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('[${post['category']}]', style: textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Text(post['title'] as String, style: textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(_nicknameOf(post), style: textTheme.bodyMedium),
                        if (post['event_at'] != null) ...[
                          const SizedBox(height: 12),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.event, size: 20),
                                      const SizedBox(width: 8),
                                      Text(_formatEventAt(post['event_at'] as String)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.place_outlined, size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          (post['facilities'] as Map?)?['name'] as String? ?? '',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        const Divider(height: 32),
                        Text(post['content'] as String, style: textTheme.bodyLarge),
                      ],
                    );
                  },
                ),
                const Divider(height: 32),
                Text('댓글', style: textTheme.titleLarge),
                const SizedBox(height: 8),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _commentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Text('댓글을 불러오지 못했습니다: ${snapshot.error}');
                    }
                    final comments = snapshot.data ?? [];
                    if (comments.isEmpty) {
                      return const Text('첫 댓글을 남겨보세요.');
                    }
                    return Column(
                      children: [
                        for (final comment in comments)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(comment['content'] as String),
                            subtitle: Text(_nicknameOf(comment)),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: '댓글을 입력하세요',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _isPostingComment
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _isPostingComment ? null : _submitComment,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/meetup_category.dart';
import '../core/report.dart';
import '../meetup/new_meetup_page.dart';
import '../app_theme.dart';
import '../ui/design_widgets.dart';
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
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
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
        .select('id, content, created_at, author_id, profiles(nickname)')
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

  String _timeOf(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.parse(iso).toLocal();
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}.${dt.day} ${dt.hour}:$minute';
  }

  TagTone _toneOf(String category) => switch (category) {
        '자유게시판' => TagTone.lavender,
        '건강정보' => TagTone.mint,
        '나눔' || '도움요청' || '나눔·도움요청' => TagTone.blue,
        _ => TagTone.neutral,
      };

  Widget _meetupCard(Map<String, dynamic> post, TextTheme textTheme) {
    final eventAt = DateTime.parse(post['event_at'] as String).toLocal();
    final upcoming = eventAt.isAfter(DateTime.now());
    final minute = eventAt.minute.toString().padLeft(2, '0');
    final placeName = (post['facilities'] as Map?)?['name'] as String? ?? '';
    final rowStyle = textTheme.bodyMedium?.copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: AppColors.scheduleText,
    );
    return SectionCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DateBlock(date: eventAt),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  label: upcoming ? '예정' : '완료',
                  tone: upcoming ? StatusPillTone.success : StatusPillTone.neutral,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${eventAt.hour}:$minute', style: rowStyle)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.place_outlined, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(placeName, style: rowStyle)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
              if (!isAuthor) {
                return TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.scheduleText,
                    minimumSize: const Size(0, 48),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => showReportFlow(context, postId: widget.postId),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('신고하기'),
                );
              }
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
                      return Center(
                        child: Text(
                          '불러오지 못했습니다: ${snapshot.error}',
                          style: textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final post = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionCard(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TagBadge(
                                label: post['category'] as String,
                                tone: _toneOf(post['category'] as String),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                post['title'] as String,
                                style: textTheme.titleLarge?.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _nicknameOf(post),
                                style: textTheme.bodyMedium?.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                post['content'] as String,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  height: 1.5,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (post['event_at'] != null) ...[
                          const SizedBox(height: 12),
                          _meetupCard(post, textTheme),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _commentsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '댓글을 불러오지 못했습니다: ${snapshot.error}',
                          style: textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final comments = snapshot.data ?? [];
                    final myId = Supabase.instance.client.auth.currentUser!.id;
                    return SectionCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '댓글 ${comments.length}',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (comments.isEmpty)
                            Text('첫 댓글을 남겨보세요.', style: textTheme.bodyMedium),
                          for (final comment in comments)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.tint,
                                    child: Text(
                                      _nicknameOf(comment).isEmpty ? '?' : _nicknameOf(comment).characters.first,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          spacing: 8,
                                          children: [
                                            Text(
                                              _nicknameOf(comment),
                                              style: textTheme.bodyMedium?.copyWith(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            Text(
                                              _timeOf(comment['created_at'] as String?),
                                              style: textTheme.bodyMedium?.copyWith(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          comment['content'] as String,
                                          style: textTheme.bodyMedium?.copyWith(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (comment['author_id'] != myId)
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppColors.scheduleText,
                                        minimumSize: const Size(48, 48),
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                      onPressed: () => showReportFlow(
                                        context,
                                        commentId: comment['id'] as String,
                                      ),
                                      icon: const Icon(Icons.flag_outlined, size: 18),
                                      label: const Text('신고'),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.navBorder)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
                    const SizedBox(width: 4),
                    IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      color: AppColors.primary,
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
          ),
        ],
      ),
    );
  }
}

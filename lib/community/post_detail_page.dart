import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../core/meetup_category.dart';
import '../core/report.dart';
import '../core/time_ago.dart';
import '../activity/activity_map_page.dart';
import '../meetup/new_meetup_page.dart';
import '../social/neighborhood_feed.dart';
import '../social/neighborhood_repository.dart';
import '../social/social_media.dart';
import 'new_post_page.dart';

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    super.key,
    required this.postId,
    this.onClose,
    this.onEdit,
  });
  final String postId;
  final VoidCallback? onClose;
  final Future<bool?> Function(Map<String, dynamic>)? onEdit;
  @override
  State<PostDetailPage> createState() => _PostState();
}

class _PostState extends State<PostDetailPage> {
  final commentsKey = GlobalKey();
  final comment = TextEditingController();
  final focus = FocusNode();
  late Future<SocialData> data = load();
  late Future<List<SocialData>> replies = loadReplies();
  bool busy = false, sending = false, showInput = false;
  String? failedComment, draftId;
  SupabaseClient get client => Supabase.instance.client;
  Future<SocialData> load() async {
    final p = await client
        .from('posts')
        .select(
          '*,facilities(id,name,address,lat,lng,category,telephone),profiles(nickname,region_sigungu)',
        )
        .eq('id', widget.postId)
        .single();
    p['extras_available'] = await NeighborhoodRepository().enrich([p]);
    return p;
  }

  Future<List<SocialData>> loadReplies() async => List<SocialData>.from(
    await client
        .from('comments')
        .select('id,content,created_at,author_id,profiles(nickname)')
        .eq('post_id', widget.postId)
        .order('created_at'),
  );
  void reload() {
    setState(() {
      data = load();
      replies = loadReplies();
    });
  }

  void close([bool changed = false]) {
    widget.onClose != null
        ? widget.onClose!()
        : Navigator.pop(context, changed);
  }

  @override
  void dispose() {
    comment.dispose();
    focus.dispose();
    super.dispose();
  }

  String nickname(Map p) => '${p['profiles']?['nickname'] ?? '이웃'}';
  Future<void> menu(SocialData p) async {
    final own = p['author_id'] == client.auth.currentUser!.id;
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(own ? '내 글 관리' : '이 글에서 할 수 있는 일', style: petText(23)),
              const SizedBox(height: 14),
              if (own) ...[
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('수정하기'),
                  onTap: () => Navigator.pop(c, 'edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text('삭제하기'),
                  onTap: () => Navigator.pop(c, 'delete'),
                ),
              ] else ...[
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('신고하기'),
                  onTap: () => Navigator.pop(c, 'report'),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text('${nickname(p)} 님 차단하기'),
                  onTap: () => Navigator.pop(c, 'block'),
                ),
              ],
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (v == 'report') await showReportFlow(context, postId: widget.postId);
    if (v == 'block' &&
        await activityDialog(
          context,
          title: '${nickname(p)} 님을 차단할까요?',
          message: '차단하면 이 분의 글과 댓글이 보이지 않아요. 내 정보에서 해제할 수 있어요.',
          action: '차단하기',
          icon: Icons.lock_outline,
        )) {
      try {
        await NeighborhoodRepository().block(p['author_id']);
        if (mounted) close(true);
      } catch (_) {
        if (mounted) await activityFailure(context, title: '차단하지 못했어요');
      }
    }
    if (v == 'delete' &&
        await activityDialog(
          context,
          title: p['category'] == kMeetupCategory
              ? '모임 글을 삭제할까요?'
              : '이 글을 지울까요?',
          message: '지운 글과 댓글은 되돌릴 수 없어요.',
          action: '삭제하기',
          color: Colors.red,
        )) {
      try {
        await client.from('posts').delete().eq('id', widget.postId);
        if (mounted) close(true);
      } catch (_) {
        if (mounted) await activityFailure(context, title: '삭제하지 못했어요');
      }
    }
    if (v == 'edit') {
      final changed = widget.onEdit != null
          ? await widget.onEdit!(p)
          : mounted
          ? await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => p['category'] == kMeetupCategory
                    ? NewMeetupPage(
                        existingPost: {...p, 'facility': p['facilities']},
                      )
                    : NewPostPage(existingPost: p),
              ),
            )
          : null;
      if (changed == true && mounted) reload();
    }
  }

  String newId() {
    final r = Random.secure();
    final h = List.generate(16, (_) => r.nextInt(256));
    h[6] = (h[6] & 15) | 64;
    h[8] = (h[8] & 63) | 128;
    final s = h.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  Future<void> send() async {
    final text = comment.text.trim();
    if (text.isEmpty || sending) return;
    if (text.length > 1000) return;
    if (failedComment != text) draftId = newId();
    draftId ??= newId();
    setState(() => sending = true);
    try {
      try {
        await client.from('comments').insert({
          'id': draftId,
          'post_id': widget.postId,
          'author_id': client.auth.currentUser!.id,
          'content': text,
        });
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow;
        final row = await client
            .from('comments')
            .select('content,author_id,post_id')
            .eq('id', draftId!)
            .single();
        if (row['content'] != text ||
            row['author_id'] != client.auth.currentUser!.id ||
            row['post_id'] != widget.postId) {
          rethrow;
        }
      }
      if (!mounted) return;
      comment.clear();
      setState(() {
        failedComment = null;
        draftId = null;
        replies = loadReplies();
      });
    } catch (_) {
      if (mounted) setState(() => failedComment = text);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> join(SocialData p) async {
    if (busy) return;
    final joined = p['joined'] == true;
    if (!await activityDialog(
      context,
      title: joined ? '참여를 취소할까요?' : '이 모임에 참여할까요?',
      message: joined
          ? '취소한 자리는 다른 이웃이 참여할 수 있어요.'
          : '${p['title']}\n${socialTime('${p['event_at']}')}',
      action: joined ? '참여 취소하기' : '참여하기',
      icon: Icons.groups_outlined,
      color: joined ? PetColors.orange : PetColors.green,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await NeighborhoodRepository().participate(widget.postId, !joined);
      if (mounted) reload();
    } on PostgrestException catch (e) {
      if (mounted) {
        await activityFailure(
          context,
          title: '참여 상태를 바꾸지 못했어요',
          message: e.code == 'P0001' ? e.message : '잠시 후 다시 시도해 주세요.',
        );
      }
    } catch (_) {
      if (mounted) await activityFailure(context, title: '참여 상태를 바꾸지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> like(SocialData p) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await NeighborhoodRepository().like(widget.postId, p['liked'] != true);
      if (mounted) reload();
    } catch (_) {
      if (mounted) await activityFailure(context, title: '공감을 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void toComments() {
    setState(() => showInput = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
    if (commentsKey.currentContext != null) {
      Scrollable.ensureVisible(
        commentsKey.currentContext!,
        duration: const Duration(milliseconds: 200),
      );
    }
    focus.requestFocus();
  }

  Widget image(String path) => FutureBuilder<String>(
    future: SocialMedia.url(path),
    builder: (c, s) => s.hasData
        ? Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                s.data!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Text('사진을 불러오지 못했어요'),
              ),
            ),
          )
        : const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(Icons.image_outlined),
          ),
  );
  @override
  Widget build(BuildContext c) => FutureBuilder<SocialData>(
    future: data,
    builder: (c, s) {
      final p = s.data;
      final meetup = p?['category'] == kMeetupCategory;
      final own = p?['author_id'] == client.auth.currentUser?.id;
      final ended = p != null && meetupEnded(p);
      return NeighborhoodScreen(
        title: meetup ? '모임 상세' : '게시글',
        tint: meetup ? neighborhoodMint : neighborhoodLavender,
        onBack: () => close(),
        actions: [
          if (p != null)
            IconButton(
              tooltip: '더보기',
              onPressed: () => menu(p),
              icon: const Icon(Icons.more_horiz),
            ),
        ],
        bottom: p == null
            ? null
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (meetup)
                    Row(
                      children: [
                        Expanded(
                          child: ActivityButton(
                            '댓글',
                            light: true,
                            onTap: toComments,
                            icon: Icons.chat_bubble_outline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ActivityButton(
                            ended
                                ? '참여 기간이 끝났어요'
                                : own
                                ? '모임 수정'
                                : p['joined'] == true
                                ? '참여 취소'
                                : '참여하기',
                            onTap: ended || busy
                                ? null
                                : own
                                ? () => menu(p)
                                : p['extras_available'] == true
                                ? () => join(p)
                                : () => activityFailure(
                                    context,
                                    title: '참여 현황을 확인하지 못했어요',
                                  ),
                            icon: Icons.groups_outlined,
                          ),
                        ),
                      ],
                    ),
                  if (!meetup || showInput)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: comment,
                              focusNode: focus,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 1000,
                              decoration: const InputDecoration(
                                hintText: '댓글을 입력하세요',
                                counterText: '',
                              ),
                              onSubmitted: (_) => send(),
                            ),
                          ),
                          IconButton(
                            tooltip: '댓글 보내기',
                            onPressed: sending ? null : send,
                            icon: const Icon(
                              Icons.send_rounded,
                              color: PetColors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
        child: s.connectionState != ConnectionState.done
            ? const NeighborhoodLoading()
            : s.hasError
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  ActivityEmpty(
                    '글을 불러오지 못했어요',
                    message: '삭제됐거나 열람할 수 없는 글일 수 있어요.',
                    action: '다시 시도',
                    onAction: reload,
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                children: [
                  if (meetup) ...[
                    NeighborhoodHero(
                      title: '${p!['title']}',
                      subtitle: '개설자 ${nickname(p)}',
                      tags: [
                        PetPill(
                          '${p['meetup_topic'] ?? '동네 모임'}',
                          color: Colors.white,
                          ink: PetColors.green,
                        ),
                        PetPill(
                          ended
                              ? '지난 모임'
                              : p['joined'] == true
                              ? '참여 중'
                              : '모집 중',
                          color: PetColors.yellow,
                          ink: PetColors.orange,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: (MediaQuery.sizeOf(c).width - 44) / 2,
                          child: ActivityCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '날짜',
                                  style: petText(
                                    15,
                                    color: PetColors.secondary,
                                  ),
                                ),
                                Text(
                                  '${DateTime.parse(p['event_at']).toLocal().month}월 ${DateTime.parse(p['event_at']).toLocal().day}일',
                                  style: petText(24),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: (MediaQuery.sizeOf(c).width - 44) / 2,
                          child: ActivityCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '시간',
                                  style: petText(
                                    15,
                                    color: PetColors.secondary,
                                  ),
                                ),
                                Text(
                                  socialTime(p['event_at']),
                                  style: petText(23),
                                ),
                                Text(
                                  '약 ${p['duration_minutes'] ?? 60}분',
                                  style: petText(
                                    15,
                                    color: PetColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ActivityCard(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place_outlined,
                            color: PetColors.green,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${p['facilities']?['name'] ?? '장소 확인 필요'}',
                              style: petText(19),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: p['facilities'] == null
                                ? null
                                : () => Navigator.push(
                                    c,
                                    PageRouteBuilder(
                                      transitionDuration: Duration.zero,
                                      reverseTransitionDuration: Duration.zero,
                                      pageBuilder: (_, _, _) => ActivityMapPage(
                                        program: {
                                          ...Map<String, dynamic>.from(
                                            p['facilities'],
                                          ),
                                          'title': p['title'],
                                          'place_name': p['facilities']['name'],
                                        },
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.map_outlined),
                            label: const Text('지도'),
                          ),
                        ],
                      ),
                    ),
                    const NeighborhoodHeading('모임 소개'),
                    ActivityCard(
                      child: Text(
                        '${p['content']}',
                        style: petText(19, weight: FontWeight.w500),
                      ),
                    ),
                    NeighborhoodHeading(
                      '참여하는 이웃',
                      count: p['member_count'] == null
                          ? '확인 필요'
                          : '${p['member_count']}/${p['meetup_capacity'] ?? 10}명',
                    ),
                    ActivityCard(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (p['participants'] is List)
                            for (final r in p['participants'])
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  NeighborAvatar(
                                    '${r['nickname']}',
                                    radius: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Text('${r['nickname']}', style: petText(16)),
                                ],
                              )
                          else
                            Text('참여 현황을 확인할 수 없어요', style: petText(16)),
                        ],
                      ),
                    ),
                  ] else
                    ActivityCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              NeighborAvatar(nickname(p!)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(nickname(p), style: petText(18)),
                              ),
                              PetPill(
                                socialCategory('${p['category']}'),
                                fontSize: 12,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('${p['title']}', style: petText(24)),
                          const SizedBox(height: 12),
                          Text(
                            '${p['content']}',
                            style: petText(18, weight: FontWeight.w500),
                          ),
                          for (final path in p['image_paths'] as List? ?? [])
                            image('$path'),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: busy ? null : () => like(p),
                                icon: Icon(
                                  p['liked'] == true
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: PetColors.pink,
                                ),
                                label: Text('공감 ${p['likes'] ?? '—'}'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.push(
                                  c,
                                  MaterialPageRoute(
                                    builder: (_) => const NewMeetupPage(),
                                  ),
                                ),
                                icon: const Icon(Icons.groups_outlined),
                                label: const Text('동네 모임으로'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  NeighborhoodHeading(
                    '댓글',
                    color: meetup ? PetColors.green : PetColors.purple,
                  ),
                  SizedBox(key: commentsKey),
                  FutureBuilder<List<SocialData>>(
                    future: replies,
                    builder: (c, r) => r.hasError
                        ? ActivityEmpty(
                            '댓글을 불러오지 못했어요',
                            action: '다시 시도',
                            onAction: () {
                              setState(() => replies = loadReplies());
                            },
                          )
                        : r.connectionState != ConnectionState.done
                        ? const Center(child: CircularProgressIndicator())
                        : ActivityCard(
                            child: Column(
                              children: [
                                if (r.data!.isEmpty)
                                  Text(
                                    '첫 댓글을 남겨 주세요',
                                    style: petText(
                                      17,
                                      color: PetColors.secondary,
                                    ),
                                  ),
                                for (final x in r.data!)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        NeighborAvatar(nickname(x), radius: 17),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                nickname(x),
                                                style: petText(16),
                                              ),
                                              Text(
                                                timeAgo(
                                                  DateTime.tryParse(
                                                        '${x['created_at']}',
                                                      )?.toLocal() ??
                                                      DateTime.now(),
                                                ),
                                                style: petText(
                                                  12,
                                                  color: PetColors.secondary,
                                                ),
                                              ),
                                              Text(
                                                '${x['content']}',
                                                style: petText(
                                                  18,
                                                  weight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (x['author_id'] !=
                                            client.auth.currentUser!.id)
                                          IconButton(
                                            tooltip: '댓글 신고',
                                            onPressed: () => showReportFlow(
                                              c,
                                              commentId: x['id'],
                                            ),
                                            icon: const Icon(
                                              Icons.flag_outlined,
                                              size: 18,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  if (failedComment != null)
                    ActivityCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '보내지 못했어요',
                            style: petText(15, color: Colors.red),
                          ),
                          Text(failedComment!, style: petText(18)),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: sending ? null : send,
                                child: const Text('다시 보내기'),
                              ),
                              TextButton(
                                onPressed: () {
                                  comment.clear();
                                  setState(() => failedComment = null);
                                },
                                child: const Text('지우기'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      );
    },
  );
}

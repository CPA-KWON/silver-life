import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../community/post_detail_page.dart';
import '../community/new_post_page.dart';
import '../meetup/new_meetup_page.dart';
import '../social/neighborhood_feed.dart';
import '../social/neighborhood_repository.dart';

class MyPostListPage extends StatefulWidget {
  const MyPostListPage({
    super.key,
    required this.title,
    required this.isMeetup,
  });
  final String title;
  final bool isMeetup;
  @override
  State<MyPostListPage> createState() => _MyPostsState();
}

class _MyPostsState extends State<MyPostListPage> {
  bool alternate = false;
  late Future<List<SocialData>> data = load();
  Future<List<SocialData>> load() async {
    final c = Supabase.instance.client, u = c.auth.currentUser!.id;
    if (!widget.isMeetup && alternate) {
      return List<SocialData>.from(
        await c
            .from('comments')
            .select('*,posts(id,title)')
            .eq('author_id', u)
            .order('created_at', ascending: false),
      );
    }
    var q = c
        .from('posts')
        .select(
          '*,comments(count),facilities(id,name,address,lat,lng,category,telephone),profiles(nickname)',
        )
        .eq('author_id', u);
    q = widget.isMeetup ? q.eq('category', '동네모임') : q.neq('category', '동네모임');
    final rows = List<SocialData>.from(
      await q.order('created_at', ascending: false),
    );
    await NeighborhoodRepository().enrich(rows);
    return rows;
  }

  void refresh() => setState(() {
    data = load();
  });
  Future<void> open(Widget p) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => p));
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: widget.title,
    tint: widget.isMeetup ? neighborhoodMint : neighborhoodLavender,
    bottom: widget.isMeetup
        ? ActivityButton(
            '새 모임 만들기',
            light: true,
            icon: Icons.add,
            onTap: () => open(const NewMeetupPage()),
          )
        : null,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: false,
                label: Text(widget.isMeetup ? '예정 모임' : '글'),
              ),
              ButtonSegment(
                value: true,
                label: Text(widget.isMeetup ? '지난 모임' : '댓글'),
              ),
            ],
            selected: {alternate},
            onSelectionChanged: (v) {
              alternate = v.first;
              refresh();
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<SocialData>>(
            future: data,
            builder: (c, s) {
              final rows = (s.data ?? [])
                  .where((p) => !widget.isMeetup || meetupEnded(p) == alternate)
                  .toList();
              return s.connectionState != ConnectionState.done
                  ? const NeighborhoodLoading()
                  : s.hasError
                  ? ActivityEmpty(
                      '내역을 불러오지 못했어요',
                      action: '다시 시도',
                      onAction: refresh,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (rows.isEmpty)
                          ActivityEmpty(
                            widget.isMeetup
                                ? '아직 만든 모임이 없어요'
                                : alternate
                                ? '아직 쓴 댓글이 없어요'
                                : '아직 쓴 글이 없어요',
                            action: widget.isMeetup ? '모임 만들기' : '글쓰기',
                            onAction: () => open(
                              widget.isMeetup
                                  ? const NewMeetupPage()
                                  : const NewPostPage(),
                            ),
                          ),
                        for (final p in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: ActivityCard(
                              onTap: () => open(
                                PostDetailPage(
                                  postId: !widget.isMeetup && alternate
                                      ? p['post_id']
                                      : p['id'],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${p['title'] ?? p['posts']?['title'] ?? '원문 글'}',
                                    style: petText(21),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    !widget.isMeetup && alternate
                                        ? '${p['content']}'
                                        : '${p['category']} ${widget.isMeetup ? '· ${p['event_at'] ?? ''}' : ''}',
                                    style: petText(
                                      16,
                                      color: PetColors.secondary,
                                    ),
                                  ),
                                  if (widget.isMeetup) ...[
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        TextButton(
                                          onPressed: () => open(
                                            NewMeetupPage(
                                              existingPost: {
                                                ...p,
                                                'facility': p['facilities'],
                                              },
                                            ),
                                          ),
                                          child: const Text('수정'),
                                        ),
                                        TextButton(
                                          onPressed: () => open(
                                            PostDetailPage(postId: p['id']),
                                          ),
                                          child: const Text('모임 보기'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    );
            },
          ),
        ),
      ],
    ),
  );
}

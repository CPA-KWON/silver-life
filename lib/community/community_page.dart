import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'new_post_page.dart';
import 'post_detail_page.dart';

const kPostCategories = ['자유게시판', '동네모임', '건강정보', '나눔·도움요청'];

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  String? _categoryFilter;
  late Future<List<Map<String, dynamic>>> _postsFuture;

  @override
  void initState() {
    super.initState();
    _postsFuture = _fetchPosts();
  }

  Future<List<Map<String, dynamic>>> _fetchPosts() async {
    final client = Supabase.instance.client;
    final builder = client
        .from('posts')
        .select('id, title, category, created_at, profiles(nickname)');
    final filtered = _categoryFilter == null
        ? builder
        : builder.eq('category', _categoryFilter!);
    final result = await filtered.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(result);
  }

  void _refresh() {
    // Must be a block body: an arrow body's value would be the Future
    // that _fetchPosts() returns, and setState() rejects a callback that
    // returns a Future instead of void.
    setState(() {
      _postsFuture = _fetchPosts();
    });
  }

  void _setCategory(String? category) {
    setState(() {
      _categoryFilter = category;
      _postsFuture = _fetchPosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _CategoryFilterBar(selected: _categoryFilter, onSelected: _setCategory),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
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
                  return const Center(child: Text('아직 게시글이 없습니다.'));
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.separated(
                    itemCount: posts.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final post = posts[i];
                      final nickname =
                          (post['profiles'] as Map?)?['nickname'] as String? ?? '알 수 없음';
                      return ListTile(
                        title: Text(
                          post['title'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '[${post['category']}] $nickname',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PostDetailPage(postId: post['id'] as String),
                            ),
                          );
                          _refresh();
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const NewPostPage()),
          );
          // Always refresh on return, not just when NewPostPage reported
          // success — a stale list is worse than one harmless extra fetch.
          _refresh();
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('전체'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in kPostCategories)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(category),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
              ),
            ),
        ],
      ),
    );
  }
}

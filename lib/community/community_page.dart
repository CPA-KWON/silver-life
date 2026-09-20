import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/region_scope.dart';
import '../core/meetup_category.dart';
import 'new_post_page.dart';
import 'post_detail_page.dart';

// 동네모임 lives in its own tab (see lib/meetup) with its own date/place
// fields, not in the general board.
const kPostCategories = ['자유게시판', '건강정보', '나눔·도움요청'];

class CommunityPage extends StatefulWidget {
  const CommunityPage({super.key});

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  String? _categoryFilter;
  // Defaults to 시도 (the broader of the two remaining scopes) rather than
  // the viewer's exact 시군구, so a brand-new user's district being empty
  // doesn't mean an empty feed on first open.
  RegionScope _regionScope = RegionScope.sido;
  String? _mySido;
  String? _mySigungu;
  Future<List<Map<String, dynamic>>>? _postsFuture;

  @override
  void initState() {
    super.initState();
    _loadMyRegion();
  }

  Future<void> _loadMyRegion() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('region_sido, region_sigungu')
        .eq('id', userId)
        .single();
    if (mounted) {
      setState(() {
        _mySido = profile['region_sido'] as String;
        _mySigungu = profile['region_sigungu'] as String;
        _postsFuture = _fetchPosts();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPosts() async {
    final client = Supabase.instance.client;
    var builder = client
        .from('posts')
        .select(
          'id, title, category, created_at, profiles!inner(nickname, region_sido, region_sigungu)',
        )
        .neq('category', kMeetupCategory)
        .eq('profiles.region_sido', _mySido!);
    if (_categoryFilter != null) {
      builder = builder.eq('category', _categoryFilter!);
    }
    if (_regionScope == RegionScope.sigungu) {
      builder = builder.eq('profiles.region_sigungu', _mySigungu!);
    }
    final result = await builder.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(result);
  }

  void _setRegionScope(RegionScope scope) {
    setState(() {
      _regionScope = scope;
      _postsFuture = _fetchPosts();
    });
  }

  void _refresh() {
    if (_mySido == null) return;
    // Must be a block body: an arrow body's value would be the Future
    // that _fetchPosts() returns, and setState() rejects a callback that
    // returns a Future instead of void.
    setState(() {
      _postsFuture = _fetchPosts();
    });
  }

  void _setCategory(String? category) {
    if (_mySido == null) return;
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
          RegionScopeBar(
            scope: _regionScope,
            mySido: _mySido,
            mySigungu: _mySigungu,
            onChanged: _mySido == null ? null : _setRegionScope,
          ),
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
                    padding: const EdgeInsets.all(16),
                    itemCount: posts.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final post = posts[i];
                      final nickname =
                          (post['profiles'] as Map?)?['nickname'] as String? ?? '알 수 없음';
                      final subtitle = '[${post['category']}] $nickname';
                      return Card(
                        child: ListTile(
                          title: Text(
                            post['title'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            subtitle,
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
                        ),
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
    return Container(
      height: 56,
      color: Colors.white,
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

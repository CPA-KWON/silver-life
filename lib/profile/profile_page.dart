import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../community/post_detail_page.dart';
import '../core/comment_count.dart';
import '../core/meetup_category.dart';
import '../core/region_picker.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  String? _sido;
  String? _sigungu;
  late Future<Map<String, dynamic>> _profileFuture;
  late Future<List<Map<String, dynamic>>> _myPostsFuture;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
    _myPostsFuture = _loadMyPosts();
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadProfile() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('id', userId)
        .single();
    _nicknameController.text = profile['nickname'] as String;
    _sido = profile['region_sido'] as String;
    _sigungu = profile['region_sigungu'] as String;
    return profile;
  }

  Future<List<Map<String, dynamic>>> _loadMyPosts() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    final result = await Supabase.instance.client
        .from('posts')
        .select('id, title, category, created_at, comments(count)')
        .eq('author_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(result);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('profiles').update({
        'nickname': _nicknameController.text.trim(),
        'region_sido': _sido,
        'region_sigungu': _sigungu,
      }).eq('id', userId);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final message = e.code == '23505' ? '이미 사용 중인 닉네임입니다.' : '저장에 실패했습니다: ${e.message}';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('불러오지 못했습니다: ${snapshot.error}'));
        }

        final profile = snapshot.data!;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('이름', style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                              profile['name'] as String,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            Text('가입일', style: Theme.of(context).textTheme.bodyMedium),
                            Text(
                              (profile['created_at'] as String).split('T').first,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nicknameController,
                      decoration: const InputDecoration(labelText: '닉네임'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty) ? '닉네임을 입력해주세요' : null,
                    ),
                    const SizedBox(height: 16),
                    RegionPicker(
                      initialSido: _sido,
                      initialSigungu: _sigungu,
                      onChanged: (sido, sigungu) {
                        _sido = sido;
                        _sigungu = sigungu;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('저장'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Supabase.instance.client.auth.signOut(),
                      child: const Text('로그아웃'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _MyPostsSection(myPostsFuture: _myPostsFuture),
            ],
          ),
        );
      },
    );
  }
}

class _MyPostsSection extends StatelessWidget {
  const _MyPostsSection({required this.myPostsFuture});

  final Future<List<Map<String, dynamic>>> myPostsFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: myPostsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('불러오지 못했습니다: ${snapshot.error}');
        }
        final posts = snapshot.data ?? [];
        final myMeetups = posts.where((p) => p['category'] == kMeetupCategory).toList();
        final myCommunityPosts = posts.where((p) => p['category'] != kMeetupCategory).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MyPostList(title: '내가 쓴 모임 글', posts: myMeetups),
            const SizedBox(height: 16),
            _MyPostList(title: '내가 쓴 커뮤니티 글', posts: myCommunityPosts),
          ],
        );
      },
    );
  }
}

class _MyPostList extends StatelessWidget {
  const _MyPostList({required this.title, required this.posts});

  final String title;
  final List<Map<String, dynamic>> posts;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (posts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('작성한 글이 없습니다.'),
          )
        else
          for (final post in posts)
            Card(
              child: ListTile(
                title: Text(
                  post['title'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('[${post['category']}]'),
                trailing: CommentCountBadge(commentCountOf(post)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PostDetailPage(postId: post['id'] as String),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

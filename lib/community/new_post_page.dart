import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../social/social_form_widgets.dart';
import '../social/social_media.dart';
import 'community_page.dart' show kPostCategories;

class NewPostPage extends StatefulWidget {
  const NewPostPage({super.key, this.existingPost, this.onFinished});
  final Map<String, dynamic>? existingPost;
  final ValueChanged<bool>? onFinished;
  @override
  State<NewPostPage> createState() => _NewPostState();
}

class _NewPostState extends State<NewPostPage> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.existingPost?['title']),
      body = TextEditingController(text: widget.existingPost?['content']);
  late String? category = widget.existingPost?['category'];
  bool busy = false;
  final photos = <XFile>[];
  late final paths = List<String>.from(
    widget.existingPost?['image_paths'] ?? [],
  );
  bool get editing => widget.existingPost != null;
  void finish(bool v) {
    widget.onFinished != null
        ? widget.onFinished!(v)
        : Navigator.pop(context, v);
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> photo() async {
    if (paths.length + photos.length >= 5) return;
    try {
      final image = await SocialMedia.choose();
      if (image != null && mounted) setState(() => photos.add(image));
    } catch (_) {
      if (mounted) await activityFailure(context, title: '사진을 고르지 못했어요');
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (category == null) {
      await activityFailure(context, title: '게시판을 골라 주세요');
      return;
    }
    setState(() => busy = true);
    final uploaded = <String>[];
    var saved = false;
    try {
      for (final p in photos) {
        uploaded.add(await SocialMedia.upload(p));
      }
      final c = Supabase.instance.client;
      final data = <String, dynamic>{
        'category': category,
        'title': title.text.trim(),
        'content': body.text.trim(),
        if (editing || paths.isNotEmpty || uploaded.isNotEmpty)
          'image_paths': [...paths, ...uploaded],
      };
      if (editing) {
        final rows = await c
            .from('posts')
            .update(data)
            .eq('id', widget.existingPost!['id'])
            .select('id');
        if (rows.isEmpty) throw StateError('수정 권한이 없어요');
      } else {
        await c.from('posts').insert({
          ...data,
          'author_id': c.auth.currentUser!.id,
        });
      }
      saved = true;
      if (mounted) finish(true);
    } catch (_) {
      if (!saved) {
        try {
          await SocialMedia.remove(uploaded);
        } catch (_) {}
      }
      if (mounted) {
        await activityFailure(
          context,
          title: editing ? '수정하지 못했어요' : '글을 올리지 못했어요',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: editing ? '글 수정' : '글쓰기',
    tint: neighborhoodLavender,
    onBack: () => finish(false),
    bottom: ActivityButton(
      editing ? '수정 저장하기' : '글 올리기',
      onTap: busy ? null : save,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SocialFormCard(
              '어느 게시판에 올릴까요?',
              required: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in kPostCategories)
                    ChoiceChip(
                      label: Text(v == '나눔·도움요청' ? '나눔' : v),
                      selected: category == v,
                      onSelected: (_) => setState(() => category = v),
                    ),
                ],
              ),
            ),
            SocialFormCard(
              '제목',
              required: true,
              child: TextFormField(
                controller: title,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '제목',
                  hintText: '제목을 적어 주세요',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '제목을 써 주세요' : null,
              ),
            ),
            SocialFormCard(
              '내용',
              required: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: body,
                    maxLength: 1000,
                    minLines: 7,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: '내용',
                      hintText: '이웃과 나누고 싶은 이야기를 적어 주세요',
                    ),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 5 ? '내용을 5자 이상 써 주세요' : null,
                  ),
                  for (final path in paths.toList())
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('첨부 사진'),
                      trailing: IconButton(
                        tooltip: '사진 제거',
                        onPressed: () => setState(() => paths.remove(path)),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  for (final image in photos.toList())
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: Text(image.name),
                      trailing: IconButton(
                        tooltip: '사진 제거',
                        onPressed: () => setState(() => photos.remove(image)),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: busy || paths.length + photos.length >= 5
                        ? null
                        : photo,
                    icon: const Icon(Icons.add),
                    label: Text('사진 붙이기 (${paths.length + photos.length}/5)'),
                  ),
                ],
              ),
            ),
            Text(
              '욕설·광고·사기 글과 개인정보 공개는 삼가 주세요.',
              style: petText(14, color: PetColors.secondary),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

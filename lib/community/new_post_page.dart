import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../social/social_form_widgets.dart';
import '../social/social_media.dart';
import '../social/photo_widgets.dart';
import 'community_page.dart' show kPostCategories;

class NewPostPage extends StatefulWidget {
  const NewPostPage({
    super.key,
    this.existingPost,
    this.onFinished,
    this.onCreated,
  });
  final ValueChanged<String>? onCreated;
  final Map<String, dynamic>? existingPost;
  final ValueChanged<bool>? onFinished;
  @override
  State<NewPostPage> createState() => _NewPostState();
}

class _Photo {
  _Photo({this.file, this.path});
  final XFile? file;
  String? path;
  bool loading = false, failed = false;
}

class _NewPostState extends State<NewPostPage> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.existingPost?['title']),
      body = TextEditingController(text: widget.existingPost?['content']);
  late String? category = widget.existingPost?['category'];
  bool busy = false, leaving = false, uncertainWrite = false;
  late final originals = List<String>.from(
    widget.existingPost?['image_paths'] ?? [],
  );
  late final photos = [for (final p in originals) _Photo(path: p)];
  late final String postId = widget.existingPost?['id'] ?? newPostId();
  bool get editing => widget.existingPost != null;
  bool get changed =>
      title.text != (widget.existingPost?['title'] ?? '') ||
      body.text != (widget.existingPost?['content'] ?? '') ||
      category != widget.existingPost?['category'] ||
      photos.any((p) => p.file != null) ||
      originals.join('|') != photos.map((p) => p.path).join('|');
  void finish(bool v) {
    if (v && !editing) widget.onCreated?.call(postId);
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

  Future<void> close() async {
    if (busy) return;
    if (changed &&
        !await activityDialog(
          context,
          title: '작성 중인 글을 그만 쓸까요?',
          message: '저장하지 않은 글과 사진은 사라져요.',
          action: '그만 쓰기',
          secondary: '계속 쓰기',
        )) {
      return;
    }
    if (!mounted) return;
    // If a save response was lost, retain private images; deleting them could
    // break a post that actually committed. Retrying uses the same post UUID.
    if (!uncertainWrite) {
      try {
        await SocialMedia.remove([
          for (final p in photos)
            if (p.file != null && p.path != null) p.path!,
        ]);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) finish(false);
  }

  Future<void> photo() async {
    if (busy || photos.length >= 5) return;
    final source = await choosePhotoSource(
      context,
      remaining: 5 - photos.length,
    );
    if (source == null || !mounted) return;
    try {
      final files = await SocialMedia.chooseMany(
        limit: 5 - photos.length,
        camera: source == PhotoSource.camera,
      );
      final accepted = <_Photo>[];
      for (final file in files.take(5 - photos.length)) {
        if (await file.length() > 10 * 1024 * 1024) {
          throw StateError('사진은 한 장에 10MB까지 올릴 수 있어요.');
        }
        accepted.add(_Photo(file: file));
      }
      if (mounted) setState(() => photos.addAll(accepted));
    } catch (e) {
      if (mounted) await photoError(context, e);
    }
  }

  Future<void> upload(_Photo p) async {
    if (p.file == null || p.path != null) return;
    setState(() {
      p.loading = true;
      p.failed = false;
    });
    try {
      p.path = await SocialMedia.upload(p.file!);
    } catch (_) {
      p.failed = true;
      rethrow;
    } finally {
      if (mounted) setState(() => p.loading = false);
    }
  }

  Future<void> retry(_Photo p) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await upload(p);
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '사진을 올리지 못했어요',
          message: '입력한 글은 그대로 있어요. 인터넷 연결을 확인한 뒤 사진의 다시 시도를 눌러 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(int index) async {
    if (busy) return;
    if (!await activityDialog(
      context,
      title: '이 사진을 뺄까요?',
      message: '게시글에서 이 사진이 빠져요.',
      action: '사진 빼기',
      secondary: '유지하기',
      icon: Icons.photo_outlined,
    )) {
      return;
    }
    if (!mounted) return;
    final p = photos[index];
    setState(() => photos.removeAt(index));
    if (p.file != null && p.path != null && !uncertainWrite) {
      try {
        await SocialMedia.remove([p.path!]);
      } catch (_) {}
    }
  }

  Future<void> preview(int i) async {
    final result = await Navigator.push<(String, int)>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewer(
          photos: [for (final p in photos) (file: p.file, path: p.path)],
          initialIndex: i,
          editable: !busy,
        ),
      ),
    );
    if (result == null || !mounted || busy) return;
    if (result.$1 == 'remove') {
      await remove(result.$2);
    } else {
      setState(() => photos.insert(0, photos.removeAt(result.$2)));
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    if (category == null) {
      await activityFailure(context, title: '게시판을 골라 주세요');
      return;
    }
    setState(() => busy = true);
    try {
      for (final p in photos) {
        if (p.path == null) await upload(p);
      }
      final c = Supabase.instance.client;
      final data = <String, dynamic>{
        'category': category,
        'title': title.text.trim(),
        'content': body.text.trim(),
        if (editing || photos.isNotEmpty)
          'image_paths': [for (final p in photos) p.path!],
      };
      uncertainWrite = true;
      if (editing) {
        final rows = await c
            .from('posts')
            .update(data)
            .eq('id', postId)
            .select('id');
        if (rows.isEmpty) throw StateError('수정 권한이 없어요.');
      } else {
        try {
          await c.from('posts').insert({
            ...data,
            'id': postId,
            'author_id': c.auth.currentUser!.id,
          });
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow;
          final rows = await c
              .from('posts')
              .update(data)
              .eq('id', postId)
              .eq('author_id', c.auth.currentUser!.id)
              .select('id');
          if (rows.isEmpty) rethrow;
        }
      }
      uncertainWrite = false;
      final kept = photos.map((p) => p.path).toSet();
      try {
        await SocialMedia.remove(
          originals.where((p) => !kept.contains(p)).toList(),
        );
      } catch (_) {
        /* Saved content must not be reported as failed due to unused-file cleanup. */
      }
      if (mounted) {
        setState(() => leaving = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) finish(true);
      }
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: photos.any((p) => p.failed)
              ? '사진을 올리지 못했어요'
              : editing
              ? '수정하지 못했어요'
              : '글을 올리지 못했어요',
          message: '입력한 내용은 그대로 있어요. 연결을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: NeighborhoodScreen(
      title: editing ? '글 수정' : '글쓰기',
      tint: neighborhoodLavender,
      onBack: close,
      bottom: ActivityButton(
        busy
            ? '올리는 중…'
            : editing
            ? '수정 저장하기'
            : '글 올리기',
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
                step: 1,
                required: true,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in kPostCategories)
                      ChoiceChip(
                        label: Text(v == '나눔·도움요청' ? '나눔' : v),
                        selected: category == v,
                        onSelected: busy
                            ? null
                            : (_) => setState(() => category = v),
                      ),
                  ],
                ),
              ),
              SocialFormCard(
                '제목',
                required: true,
                child: TextFormField(
                  controller: title,
                  enabled: !busy,
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
                child: TextFormField(
                  controller: body,
                  enabled: !busy,
                  maxLength: 1000,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: '내용',
                    hintText: '이웃과 나누고 싶은 이야기를 적어 주세요',
                  ),
                  validator: (v) =>
                      (v?.trim().length ?? 0) < 5 ? '내용을 5자 이상 써 주세요' : null,
                ),
              ),
              SocialFormCard(
                '사진 · 선택 · 최대 5장',
                step: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (photos.isNotEmpty)
                      LayoutBuilder(
                        builder: (c, size) => GridView.count(
                          crossAxisCount: size.maxWidth < 300 ? 2 : 3,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 10,
                          childAspectRatio: .9,
                          children: [
                            for (final (i, p) in photos.indexed)
                              PhotoTile(
                                file: p.file,
                                path: p.path,
                                index: i,
                                loading: p.loading,
                                failed: p.failed,
                                onTap: busy ? null : () => preview(i),
                                onRetry: busy ? null : () => retry(p),
                                onRemove: busy ? null : () => remove(i),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: busy || photos.length >= 5 ? null : photo,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text('사진 붙이기 (${photos.length}/5)'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      photos.length >= 5
                          ? '사진 5장을 모두 골랐어요. 뺀 뒤 다른 사진을 넣을 수 있어요.'
                          : 'JPG·PNG·WebP · 한 장에 10MB까지',
                      style: petText(14, color: PetColors.secondary),
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
    ),
  );
}

String newPostId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

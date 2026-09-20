import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'community_page.dart' show kPostCategories;

class NewPostPage extends StatefulWidget {
  const NewPostPage({super.key, this.existingPost});

  /// When set (id, category, title, content), the page edits that post
  /// (UPDATE) instead of creating a new one (INSERT).
  final Map<String, dynamic>? existingPost;

  @override
  State<NewPostPage> createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.existingPost?['title'] as String?,
  );
  late final _contentController = TextEditingController(
    text: widget.existingPost?['content'] as String?,
  );
  late String _category =
      widget.existingPost?['category'] as String? ?? kPostCategories.first;
  bool _isSaving = false;

  bool get _isEditing => widget.existingPost != null;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final client = Supabase.instance.client;
      final data = {
        'category': _category,
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
      };

      if (_isEditing) {
        await client.from('posts').update(data).eq('id', widget.existingPost!['id'] as String);
      } else {
        final userId = client.auth.currentUser!.id;
        await client.from('posts').insert({...data, 'author_id': userId});
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final action = _isEditing ? '수정' : '등록';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('글 $action에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '글 수정' : '글쓰기')),
      // Scrollable so the form doesn't overflow when the keyboard opens
      // and shrinks the available height (title/content have multiple
      // fields plus an 8-line content box).
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: '카테고리',
                ),
                items: [
                  for (final category in kPostCategories)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: '제목',
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '제목을 입력해주세요' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(
                  labelText: '내용',
                ),
                maxLines: 8,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? '내용을 입력해주세요' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? '수정하기' : '등록하기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialMedia {
  static const bucket = 'neighborhood-media';
  static Future<XFile?> choose() => ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 1600,
    maxHeight: 1600,
    imageQuality: 85,
  );
  static Future<String> upload(XFile image, {String folder = 'posts'}) async {
    final c = Supabase.instance.client, bytes = await image.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw StateError('사진은 10MB 이하로 골라 주세요.');
    }
    final mime =
        image.mimeType ??
        (image.path.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg');
    if (!['image/jpeg', 'image/png', 'image/webp'].contains(mime)) {
      throw StateError('JPG·PNG·WebP 사진을 골라 주세요.');
    }
    final path =
        '${c.auth.currentUser!.id}/$folder/${DateTime.now().microsecondsSinceEpoch}.${mime.split('/').last}';
    await c.storage
        .from(bucket)
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mime),
        );
    return path;
  }

  static Future<String> url(String path) =>
      Supabase.instance.client.storage.from(bucket).createSignedUrl(path, 300);
  static Future<void> remove(List<String> paths) async {
    if (paths.isNotEmpty) {
      await Supabase.instance.client.storage.from(bucket).remove(paths);
    }
  }
}

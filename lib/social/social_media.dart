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
  static Future<List<XFile>> chooseMany({
    required int limit,
    bool camera = false,
  }) async {
    if (camera) {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      return file == null ? [] : [file];
    }
    return ImagePicker().pickMultiImage(
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
      limit: limit,
      requestFullMetadata: false,
    );
  }

  static Future<String> upload(XFile image, {String folder = 'posts'}) async {
    final c = Supabase.instance.client, bytes = await image.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw StateError('사진은 10MB 이하로 골라 주세요.');
    }
    final String mime;
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      mime = 'image/png';
    } else if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      mime = 'image/jpeg';
    } else if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP') {
      mime = 'image/webp';
    } else {
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

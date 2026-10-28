import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ui/neighborhood_design.dart';
import 'social_media.dart';

enum PhotoSource { camera, gallery, clear }

Future<PhotoSource?> choosePhotoSource(
  BuildContext context, {
  bool avatar = false,
  int remaining = 5,
}) => showModalBottomSheet<PhotoSource>(
  context: context,
  showDragHandle: true,
  builder: (c) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(avatar ? '프로필 사진 바꾸기' : '사진 붙이기', style: petText(23)),
          if (!avatar)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '한 번에 여러 장 고를 수 있어요 (남은 $remaining장)',
                style: petText(15, color: PetColors.secondary),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final (source, icon, label) in [
                (PhotoSource.camera, Icons.photo_camera_outlined, '사진 찍기'),
                (PhotoSource.gallery, Icons.photo_library_outlined, '앨범에서 고르기'),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ActivityCard(
                      color: const Color(0xFFF2F6FA),
                      onTap: () => Navigator.pop(c, source),
                      child: Column(
                        children: [
                          Icon(icon, color: PetColors.blue, size: 30),
                          const SizedBox(height: 12),
                          Text(label, style: petText(16)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (avatar) ...[
            ActivityButton(
              '기본 이미지로 바꾸기',
              light: true,
              onTap: () => Navigator.pop(c, PhotoSource.clear),
            ),
            const SizedBox(height: 8),
          ],
          ActivityButton('닫기', light: true, onTap: () => Navigator.pop(c)),
        ],
      ),
    ),
  ),
);
Future<void> photoError(BuildContext context, Object error) async {
  if (error is PlatformException &&
      [
        'photo_access_denied',
        'camera_access_denied',
        'photo_access_restricted',
        'camera_access_restricted',
      ].contains(error.code)) {
    final go = await activityDialog(
      context,
      title: '사진 접근 권한이 필요해요',
      message: '사진을 붙이려면 설정에서 카메라 또는 사진 접근을 허용해 주세요.',
      action: '설정 열기',
      secondary: '나중에',
      icon: Icons.lock_outline,
    );
    if (go) await openAppSettings();
  } else {
    await activityFailure(
      context,
      title: '사진을 가져오지 못했어요',
      message: error is StateError
          ? error.message
          : '사진을 다시 골라 주세요. JPG·PNG·WebP, 한 장에 10MB까지 올릴 수 있어요.',
    );
  }
}

class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    this.file,
    this.path,
    required this.index,
    this.loading = false,
    this.failed = false,
    this.onRetry,
    this.onRemove,
    this.onTap,
  });
  final XFile? file;
  final String? path;
  final int index;
  final bool loading, failed;
  final VoidCallback? onRetry, onRemove, onTap;
  @override
  Widget build(BuildContext c) => AspectRatio(
    aspectRatio: .9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: onTap,
            child: SocialPhoto(file: file, path: path),
          ),
          if (loading || failed)
            ColoredBox(
              color: failed ? const Color(0xCCCB483A) : const Color(0x99142230),
              child: Center(
                child: loading
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 10),
                          Text(
                            '올리는 중',
                            style: petText(13, color: Colors.white),
                          ),
                        ],
                      )
                    : TextButton(
                        onPressed: onRetry,
                        child: Text(
                          '↻\n다시 시도',
                          textAlign: TextAlign.center,
                          style: petText(15, color: Colors.white),
                        ),
                      ),
              ),
            ),
          Positioned(
            top: 6,
            left: 6,
            child: CircleAvatar(
              radius: 11,
              backgroundColor: PetColors.blue,
              child: Text(
                '${index + 1}',
                style: petText(12, color: Colors.white),
              ),
            ),
          ),
          if (index == 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ColoredBox(
                color: const Color(0x77142230),
                child: Text(
                  '대표 사진',
                  textAlign: TextAlign.center,
                  style: petText(12, color: Colors.white),
                ),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                tooltip: '사진 ${index + 1} 빼기',
                onPressed: onRemove,
                icon: const Icon(Icons.cancel, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ),
        ],
      ),
    ),
  );
}

class SocialPhoto extends StatefulWidget {
  const SocialPhoto({super.key, this.file, this.path, this.fit = BoxFit.cover});
  final XFile? file;
  final String? path;
  final BoxFit fit;
  @override
  State<SocialPhoto> createState() => _SocialPhotoState();
}

class _SocialPhotoState extends State<SocialPhoto> {
  late Future<Object> data = load();
  Future<Object> load() async => widget.file != null
      ? await widget.file!.readAsBytes()
      : await SocialMedia.url(widget.path!);
  @override
  void didUpdateWidget(covariant SocialPhoto old) {
    super.didUpdateWidget(old);
    if (old.file != widget.file || old.path != widget.path) data = load();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<Object>(
    future: data,
    builder: (c, s) {
      Widget failed() => Center(
        child: TextButton.icon(
          onPressed: () => setState(() {
            data = load();
          }),
          icon: const Icon(Icons.refresh),
          label: const Text('사진 다시 보기'),
        ),
      );
      if (s.hasError) return failed();
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      if (s.data is Uint8List) {
        return Image.memory(
          s.data as Uint8List,
          fit: widget.fit,
          errorBuilder: (_, _, _) => failed(),
        );
      }
      return Image.network(
        s.data as String,
        fit: widget.fit,
        errorBuilder: (_, _, _) => failed(),
      );
    },
  );
}

class PhotoViewer extends StatefulWidget {
  const PhotoViewer({
    super.key,
    required this.photos,
    this.initialIndex = 0,
    this.editable = false,
  });
  final List<({XFile? file, String? path})> photos;
  final int initialIndex;
  final bool editable;
  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> {
  late int index = widget.initialIndex;
  late final PageController pages = PageController(initialPage: index);
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: const Color(0xFF14202C),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '${index + 1} / ${widget.photos.length}',
                  style: petText(18, color: Colors.white),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: pages,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => index = i),
              itemBuilder: (c, i) => Padding(
                padding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: SocialPhoto(
                      file: widget.photos[i].file,
                      path: widget.photos[i].path,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (widget.editable)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ActivityButton(
                      '☆ 대표 사진으로',
                      light: true,
                      onTap: () => Navigator.pop(c, ('cover', index)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ActivityButton(
                      '× 빼기',
                      color: Colors.redAccent,
                      onTap: () => Navigator.pop(c, ('remove', index)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

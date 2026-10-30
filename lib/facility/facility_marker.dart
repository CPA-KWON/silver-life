import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'facility_result_widgets.dart';

/// Eight cached native images for four venue types and their selected states.
/// No widget capture, frame-by-frame rasterization, or marker rebuild on drag.
class FacilityMarkerImages {
  static final _images = <String, Future<NOverlayImage>>{};
  static String kind(String category) =>
      ['약국', '경로당', '복지관'].firstWhere(category.contains, orElse: () => '병원');
  static Future<NOverlayImage> image(String category, {bool selected = false}) {
    final type = kind(category), key = '$type-$selected';
    return _images.putIfAbsent(key, () => _draw(type, selected));
  }

  static Future<NOverlayImage> _draw(String category, bool selected) async {
    const scale = 3.0;
    final recorder = ui.PictureRecorder();
    // Use a single recorder with a logical 44x50 canvas for crisp map assets.
    final c = Canvas(recorder)..scale(scale);
    final color = facilityColor(category), center = const Offset(22, 22);
    final pointer = Path()
      ..moveTo(16, 36)
      ..lineTo(22, 47)
      ..lineTo(28, 36)
      ..close();
    c.drawShadow(
      Path()..addOval(Rect.fromCircle(center: center, radius: 20)),
      Colors.black.withValues(alpha: .25),
      2,
      true,
    );
    c.drawPath(pointer, Paint()..color = selected ? color : Colors.white);
    c.drawCircle(center, 20, Paint()..color = selected ? color : Colors.white);
    c.drawCircle(
      center,
      18,
      Paint()..color = color.withValues(alpha: selected ? 1 : .10),
    );
    c.drawCircle(
      center,
      20,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7,
    );
    final icon = facilityIcon(category);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 24,
          color: selected ? Colors.white : color,
        ),
      ),
    )..layout();
    painter.paint(c, center - Offset(painter.width / 2, painter.height / 2));
    final picture = recorder.endRecording();
    final raster = await picture.toImage(132, 150);
    final bytes = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    picture.dispose();
    return NOverlayImage.fromByteArray(
      bytes!.buffer.asUint8List(),
      cacheKey: 'silver-facility-v1-$category-$selected',
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../activity/activity_design.dart';

/// NAVER official route URL scheme; omitted start uses the map app's location.
Future<void> openMapDirections(
  BuildContext c, {
  required double lat,
  required double lng,
  required String name,
}) async {
  final uri = Uri(
    scheme: 'nmap',
    host: 'route',
    path: '/walk',
    queryParameters: {
      'dlat': '$lat',
      'dlng': '$lng',
      'dname': name,
      'appname': 'com.silverlife.app',
    },
  );
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!opened) {
    try {
      opened = await launchUrl(
        Uri.https('map.naver.com', '/p/search/$name'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }
  if (!opened && c.mounted) {
    await activityFailure(
      c,
      title: '지도를 열지 못했어요',
      message: '네이버 지도 앱이나 인터넷 연결을 확인해 주세요.',
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public metadata links must never become arbitrary platform/deep-link URLs.
Uri? publicSourceUri(dynamic value) {
  final uri = Uri.tryParse('$value');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri;
}

Future<void> openPublicSource(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    if (publicSourceUri(uri.toString()) != null) {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {}
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('기관 홈페이지를 열지 못했어요. 잠시 후 다시 시도해 주세요.')),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> callFacility(BuildContext context, String telephone) async {
  bool opened = false;
  try {
    opened = await launchUrl(Uri(scheme: 'tel', path: telephone));
  } catch (_) {}
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: SelectableText('전화 앱을 열 수 없어요. 전화번호: $telephone')),
      );
  }
}

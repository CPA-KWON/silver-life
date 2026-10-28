import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../activity/activity_design.dart';

Future<void> callFacility(BuildContext context, String telephone) async {
  final number = telephone.trim();
  if (number.isEmpty) return;
  if (!await activityDialog(
    context,
    title: '전화로 문의할까요?',
    message: '휴대폰 전화 앱을 열어요.',
    action: '전화 걸기',
    icon: Icons.phone_outlined,
    color: const Color(0xFF269C69),
    rows: [('번호', number)],
  )) {
    return;
  }
  if (!context.mounted) return;
  var opened = false;
  try {
    opened = await launchUrl(
      Uri(scheme: 'tel', path: number),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}
  if (!opened && context.mounted) {
    final copy = await activityDialog(
      context,
      title: '전화를 걸 수 없어요',
      message: '이 기기에서는 전화를 열 수 없어요. 아래 번호로 직접 연락해 주세요.',
      action: '번호 복사하기',
      secondary: '닫기',
      icon: Icons.phone_disabled_outlined,
      rows: [('번호', number)],
    );
    if (copy) await Clipboard.setData(ClipboardData(text: number));
  }
}

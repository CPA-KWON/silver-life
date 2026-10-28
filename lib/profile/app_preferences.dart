import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences extends ChangeNotifier {
  static final instance = AppPreferences();
  double fontScale = 1;
  Map<String, bool> alerts = {
    '모임 알림': true,
    '프로그램 알림': true,
    '댓글 알림': true,
    '추천 소식': false,
  };
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    fontScale = (p.getDouble('font_scale') ?? 1).clamp(1, 1.25);
    for (final k in alerts.keys.toList()) {
      alerts[k] = p.getBool('alert_$k') ?? alerts[k]!;
    }
    notifyListeners();
  }

  Future<void> font(double v) async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('font_scale', v);
    fontScale = v;
    notifyListeners();
  }

  Future<void> alert(String k, bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('alert_$k', v);
    alerts[k] = v;
    notifyListeners();
  }
}

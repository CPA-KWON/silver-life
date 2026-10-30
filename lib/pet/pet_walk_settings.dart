import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Kept on this device per signed-in owner; contact details are never sent to
/// the pet API, map provider, analytics or shared result text.
class PetWalkSettings {
  PetWalkSettings(this.owner);
  final String owner;
  String name = '', phone = '', relation = '';
  Map<String, dynamic>? destination;
  DateTime? returnAt;
  String? session;
  int pausedSeconds = 0;
  DateTime? pausedAt;
  List<Map<String, dynamic>> records = [];
  String get key => 'pet_walk_safety_v1_$owner';
  static bool validPhone(String text) =>
      RegExp(r'^\+?[0-9]{8,15}$')
          .hasMatch(text.replaceAll(RegExp(r'[\s()-]'), ''));
  Future<void> load() async {
    if (owner.isEmpty) return;
    final raw = (await SharedPreferences.getInstance()).getString(key);
    if (raw == null) return;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      name = d['name'] as String? ?? '';
      phone = d['phone'] as String? ?? '';
      relation = d['relation'] as String? ?? '';
      destination = d['destination'] == null
          ? null
          : Map<String, dynamic>.from(d['destination']);
      returnAt = DateTime.tryParse('${d['returnAt']}');
      session = d['session'] as String?;
      pausedSeconds = (d['pausedSeconds'] as num?)?.toInt() ?? 0;
      pausedAt = DateTime.tryParse('${d['pausedAt']}');
      records = (d['records'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      /* Malformed device settings never blocks ending a walk. */
    }
  }

  Future<void> save() async {
    if (owner.isEmpty) return;
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode({
        'name': name,
        'phone': phone,
        'relation': relation,
        'destination': destination,
        'returnAt': returnAt?.toIso8601String(),
        'session': session,
        'pausedSeconds': pausedSeconds,
        'pausedAt': pausedAt?.toIso8601String(),
        'records': records.take(100).toList(),
      }),
    );
  }

  int activeSeconds(DateTime start, DateTime now) {
    final pending = pausedAt == null ? 0 : now.difference(pausedAt!).inSeconds;
    return (now.difference(start).inSeconds - pausedSeconds - pending).clamp(
      0,
      86400 * 7,
    );
  }
}

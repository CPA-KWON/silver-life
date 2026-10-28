import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../facility/welfare_programs.dart';

/// Descriptive data is kept separate from RPC-enrollable activities. No fake
/// dates, capacity availability, prices, enrollment IDs or rewards are created.
String welfareActivityCategory(Map<String, dynamic> p) {
  String? classify(String text) {
    if (RegExp('운동|댄스|요가|호흡|체력|안마|진료|건강|복약|심리|마음|근력|마사지|워킹').hasMatch(text)) {
      return '건강·운동';
    }
    if (RegExp('정보화|어학|교양|스마트폰|컴퓨터|디지털|영어|일본어|중국어|문학|글쓰기|AI').hasMatch(text)) {
      return '배움·디지털';
    }
    if (RegExp('음악|미술|사진|공예|노래|스케치|뜨개|악기|합창|오케스트라|팝송|하모니카|우쿨렐레|캘리')
        .hasMatch(text)) {
      return '문화·취미';
    }
    if (RegExp('이·미용|푸드|마켓|미용|생활|자활').hasMatch(text)) return '생활·기술';
    return null;
  }

  // The institution's explicit category takes precedence over title keywords.
  return classify('${p['category'] ?? ''}') ??
      classify('${p['title'] ?? ''}') ??
      '지역·이야기';
}

String _facilityKey(String name) =>
    name.replaceAll(RegExp(r'\s+|서울시립|시립|구립|어르신|노인|복지관|[%,().]'), '');

Map<String, dynamic> welfareCatalogItem(
  Map<String, dynamic> raw,
  List<Map<String, dynamic>> facilities,
  Map<String, dynamic>? pref,
) {
  final name = '${raw['facility_name']}';
  final candidates = facilities
      .where(
        (f) =>
            facilityNameMatches('${f['name']}', name) &&
            f['lat'] is num &&
            f['lng'] is num &&
            (f['lat'] as num).abs() <= 90 &&
            (f['lng'] as num).abs() <= 180,
      )
      .toList();
  final exact = candidates.where((f) => f['name'] == name).toList();
  final matches = exact.isNotEmpty ? exact : candidates;
  Map<String, dynamic>? facility;
  if (matches.isNotEmpty &&
      matches.every(
        (f) =>
            Geolocator.distanceBetween(
              (matches.first['lat'] as num).toDouble(),
              (matches.first['lng'] as num).toDouble(),
              (f['lat'] as num).toDouble(),
              (f['lng'] as num).toDouble(),
            ) <
            100,
      )) {
    facility = matches.first;
  }
  final lat = facility?['lat'] as num?, lng = facility?['lng'] as num?;
  final originLat = pref?['lat'] as num?, originLng = pref?['lng'] as num?;
  final distance =
      lat != null && lng != null && originLat != null && originLng != null
      ? Geolocator.distanceBetween(
              originLat.toDouble(),
              originLng.toDouble(),
              lat.toDouble(),
              lng.toDouble(),
            ) /
            1000
      : null;
  return {
    'id': 'welfare:${raw['id']}',
    'source': 'welfare',
    'kind': 'activity',
    'title': raw['title'],
    'description': raw['description'] ?? '',
    'category': welfareActivityCategory(raw),
    'source_category': raw['category'],
    'org_name': name,
    'place_name': name,
    'lat': lat,
    'lng': lng,
    'distance_km': distance,
    'telephone': facility?['telephone'] ?? '',
    'address': facility?['address'] ?? raw['place'] ?? '',
    'display_schedule': raw['schedule'] ?? raw['hours'] ?? '일정은 기관에 문의해 주세요',
    'display_fee':
        raw['fee'] ??
        (raw['is_free'] == true
            ? '무료'
            : raw['is_free'] == false
            ? '유료 · 금액 확인'
            : '비용은 기관에 문의해 주세요'),
    'raw_program': raw,
  };
}

class ActivityWelfareCatalog {
  ActivityWelfareCatalog(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> load(Map<String, dynamic>? pref) async {
    final raw = <Map<String, dynamic>>[];
    // Page the table; new centers/programs are not silently lost at the row cap.
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('welfare_programs')
          .select()
          .order('id')
          .range(offset, offset + 499)
          .timeout(const Duration(seconds: 10));
      raw.addAll(page);
      if (page.length < 500) break;
    }
    if (raw.isEmpty) return [];
    final keys = raw
        .map((r) => _facilityKey('${r['facility_name']}'))
        .where((k) => k.length >= 3)
        .toSet()
        .toList();
    final facilities = <Map<String, dynamic>>[];
    try {
      for (var offset = 0; offset < keys.length; offset += 20) {
        final part = keys.skip(offset).take(20);
        facilities.addAll(
          await client
              .from('facilities')
              .select('id,name,address,telephone,lat,lng')
              .or(part.map((k) => 'name.ilike.%$k%').join(','))
              .limit(500)
              .timeout(const Duration(seconds: 8)),
        );
      }
    } catch (e) {
      debugPrint('welfare facility coordinates unavailable: ${e.runtimeType}');
    }
    return [for (final row in raw) welfareCatalogItem(row, facilities, pref)];
  }
}

bool welfareMatchesPreferences(
  Map<String, dynamic> p,
  Map<String, dynamic> pref, {
  bool includeUnlocated = false,
}) {
  if (!(pref['interests'] as List? ?? []).contains(p['category'])) return false;
  final distance = p['distance_km'] as num?;
  if (distance == null) return includeUnlocated;
  return distance <= (pref['radius_km'] as num? ?? 3);
}

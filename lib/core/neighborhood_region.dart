import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../facility/facility_distance.dart';
import 'korea_regions.dart';

typedef NeighborhoodRegion = ({String sido, String sigungu});
const defaultNeighborhood = (sido: '서울특별시', sigungu: '동작구');

/// Reads the signed-in user's saved "우리 동네" (회원정보 관리), or null.
typedef SavedRegionLoader = Future<NeighborhoodRegion?> Function();

/// The district that home, 동네 모임, 커뮤니티 and 기관 공지 browse.
///
/// The user's saved "우리 동네" comes first, so changing it in 회원정보 관리
/// changes every list. Only when none is saved (or it cannot be read) does it
/// fall back to the phone's current location, then to [defaultNeighborhood].
/// Browsing only: never writes a profile or supplies a GPS fix for distances,
/// check-ins, walking rewards, or registered-resident eligibility.
class NeighborhoodRegionResolver {
  NeighborhoodRegionResolver({
    this.positionLoader = loadFacilityPosition,
    Future<List<Placemark>> Function(double, double)? geocoder,
    SavedRegionLoader? savedRegion,
  }) : geocoder = geocoder ?? _placemarks,
       savedRegion = savedRegion ?? loadSavedRegion;

  static final shared = NeighborhoodRegionResolver();

  /// Bumped when the user saves a new "우리 동네", so open lists reload.
  static final changes = ValueNotifier<int>(0);
  static void notifyChanged() => changes.value++;

  final FacilityPositionLoader positionLoader;
  final Future<List<Placemark>> Function(double, double) geocoder;
  final SavedRegionLoader savedRegion;
  Future<NeighborhoodRegion>? _pending;
  NeighborhoodRegion? _cached;
  DateTime? _until;

  static Future<List<Placemark>> _placemarks(double lat, double lng) =>
      Geocoding().placemarkFromCoordinates(
        lat,
        lng,
        locale: const Locale('ko', 'KR'),
      );

  /// The saved profile district, if it is a known 시/도 + 시/군/구 pair.
  static Future<NeighborhoodRegion?> loadSavedRegion() async {
    try {
      final client = Supabase.instance.client;
      final id = client.auth.currentUser?.id;
      if (id == null) return null;
      final row = await client
          .from('profiles')
          .select('region_sido, region_sigungu')
          .eq('id', id)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      final sido = row?['region_sido'] as String?;
      final sigungu = row?['region_sigungu'] as String?;
      if (sido == null || sigungu == null) return null;
      if (!(kKoreaRegions[sido]?.contains(sigungu) ?? false)) return null;
      return (sido: sido, sigungu: sigungu);
    } catch (_) {
      return null; // Offline or signed out: browse by location instead.
    }
  }

  Future<NeighborhoodRegion> resolve() async {
    // Read every time (one small row) so a just-saved district applies.
    final saved = await savedRegion();
    if (saved != null) return saved;
    if (_cached != null && DateTime.now().isBefore(_until!)) {
      return _cached!;
    }
    return _pending ??= _resolve().whenComplete(() => _pending = null);
  }

  Future<NeighborhoodRegion> _resolve() async {
    NeighborhoodRegion? found;
    try {
      final position = await positionLoader().timeout(
        const Duration(seconds: 3),
      );
      if (position != null) {
        final places = await geocoder(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 2));
        for (final place in places) {
          found = fromPlacemark(place);
          if (found != null) break;
        }
      }
    } catch (_) {
      // Missing permission, GPS, network, or native geocoder: usable default.
    }
    _cached = found ?? defaultNeighborhood;
    _until = DateTime.now().add(
      found == null ? const Duration(seconds: 30) : const Duration(minutes: 5),
    );
    return _cached!;
  }

  static NeighborhoodRegion? fromPlacemark(Placemark place) {
    const aliases = {
      '서울': '서울특별시',
      '서울시': '서울특별시',
      '부산': '부산광역시',
      '인천': '인천광역시',
      '대구': '대구광역시',
      '광주': '광주광역시',
      '대전': '대전광역시',
      '울산': '울산광역시',
      '세종': '세종특별자치시',
      '경기': '경기도',
      '강원도': '강원특별자치도',
      '전라북도': '전북특별자치도',
      '제주도': '제주특별자치도',
    };
    final fields =
        [
              place.administrativeArea,
              place.subAdministrativeArea,
              place.locality,
              place.subLocality,
            ]
            .whereType<String>()
            .expand((v) => v.trim().split(RegExp(r'\s+')))
            .toList();
    for (final field in fields) {
      final sido = aliases[field] ?? field;
      final districts = kKoreaRegions[sido];
      if (districts == null) continue;
      for (final district in fields) {
        if (districts.contains(district)) {
          return (sido: sido, sigungu: district);
        }
      }
    }
    return null;
  }
}

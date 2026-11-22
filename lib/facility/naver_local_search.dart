import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Thrown when the NAVER API Hub free quota is exhausted (HTTP 429), so
/// callers can show a friendly message instead of a raw error.
class FacilityRateLimitException implements Exception {
  const FacilityRateLimitException();
}

class FacilitySearchNotReadyException implements Exception {
  const FacilitySearchNotReadyException();
}

class FacilitySearchAuthException implements Exception {
  const FacilitySearchAuthException();
}

class FacilitySearchServerException implements Exception {
  const FacilitySearchServerException(this.statusCode);
  final int statusCode;

  @override
  String toString() => 'FacilitySearchServerException($statusCode)';
}

String facilitySearchErrorMessage(Object error) {
  if (error is FacilitySearchNotReadyException) {
    return '병원·약국·복지관 검색을 준비 중이에요. 지금은 경로당을 찾아볼 수 있어요.';
  }
  if (error is FacilitySearchAuthException) {
    return '로그인 상태를 확인하지 못했어요. 다시 로그인한 뒤 검색해주세요.';
  }
  if (error is FacilityRateLimitException) {
    return '검색 요청이 많아요. 잠시 후 다시 시도해주세요.';
  }
  if (error is TimeoutException) {
    return '검색 응답이 늦어지고 있어요. 잠시 후 다시 시도해주세요.';
  }
  if (error is http.ClientException) {
    return '시설 검색에 연결하지 못했어요. 인터넷 연결을 확인한 뒤 다시 시도해주세요.';
  }
  return '시설 검색이 원활하지 않아요. 잠시 후 다시 시도해주세요.';
}

class _CacheEntry<T> {
  _CacheEntry(this.value, this.fetchedAt);
  final T value;
  final DateTime fetchedAt;
}

const _cacheTtl = Duration(minutes: 5);
const _maxCacheEntries = 100;
final _searchService = FacilitySearchService();

class FacilityResult {
  const FacilityResult({
    this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.telephone,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
    this.liveOnly = false,
  });

  /// Set only when this result came from our own `facilities` table
  /// (see [searchOwnFacilities]) rather than a live NAVER search — a
  /// stable id that meetup posts (`posts.facility_id`) can reliably
  /// reference, unlike NAVER results which have no persistent identity.
  final String? id;
  final String name;
  final String category;
  final String address;
  final String telephone;
  final double lat;
  final double lng;
  final double distanceMeters;

  /// A Kakao nearest-first result. Kakao's terms allow showing it live but
  /// never storing it, so saving goes through [findStorableFacility] first.
  final bool liveOnly;
}

/// Thrown when a live-only place has no matching NAVER place to save.
class FacilityNotStorableException implements Exception {
  const FacilityNotStorableException();
}

String _stripTags(String html) => html.replaceAll(RegExp('<[^>]*>'), '');

const _hospitalTerms = [
  '병원', '의원', '한의원', '요양병원', '내과', '정형외과', '안과', '치과', //
  '이비인후과', '피부과', '신경과', '비뇨기과', '산부인과', '가정의학과', '재활의학과',
];

// Kakao category group codes: HP8 hospitals (incl. specialties), PM9 pharmacy.
final _kakaoGroups = {
  '약국': 'PM9',
  for (final term in _hospitalTerms) term: 'HP8',
};

// Kind-of-place words: like map apps, these search around the map nearest
// first, while anything else typed (a name) is matched by accuracy.
final _nearbyTerms = {
  ..._kakaoGroups.keys,
  '경로당', '복지관', '노인복지관', '사회복지관', '종합사회복지관', '보건소', //
};

/// "약국", "근처 치과" -> the word to search nearest-first; null for names.
String? nearbyTerm(String query) {
  final word = query.replaceAll(RegExp(r'(근처|주변|가까운)'), '').replaceAll(' ', '');
  return _nearbyTerms.contains(word) ? word : null;
}

String _compact(String name) => name.replaceAll(RegExp(r'[\s()·]'), '');

// "서울 중구 세종대로 110" -> "서울 중구": enough for NAVER to find the place.
String _district(String address) {
  final parts = address.split(' ').where((p) => p.isNotEmpty).toList();
  final end = parts.lastIndexWhere(
    (p) => RegExp(r'(시|군|구)$').hasMatch(p),
    parts.length > 3 ? 2 : parts.length - 1,
  );
  return parts.take(end < 0 ? 1 : end + 1).join(' ');
}

/// Keeps the existing API and query format while sharing connections, address
/// lookups and concurrent requests between home and the facility map.
class FacilitySearchService {
  FacilitySearchService({
    http.Client? client,
    Future<String> Function(double lat, double lng)? resolveArea,
    DateTime Function()? now,
    this.supabaseUrl = _supabaseUrl,
    this.supabaseAnonKey = _supabaseAnonKey,
    String? Function()? accessToken,
    this.geocodingTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _resolveArea = resolveArea ?? _reverseGeocode,
       _now = now ?? DateTime.now,
       _accessToken =
           accessToken ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken);

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String? Function() _accessToken;
  final http.Client _client;
  final Future<String> Function(double lat, double lng) _resolveArea;
  final DateTime Function() _now;
  final Duration geocodingTimeout;
  final Duration requestTimeout;
  final _results = <String, _CacheEntry<List<FacilityResult>>>{};
  final _areas = <String, _CacheEntry<String>>{};
  final _pendingSearches = <String, Future<List<FacilityResult>>>{};
  final _pendingAreas = <String, Future<String>>{};

  static Future<String> _reverseGeocode(double lat, double lng) async {
    final placemarks = await Geocoding().placemarkFromCoordinates(
      lat,
      lng,
      locale: const Locale('ko', 'KR'),
    );
    if (placemarks.isEmpty) return '';
    final place = placemarks.first;
    // Native geocoders otherwise inherit an English device locale, producing
    // queries such as 'Sogong-dong 약국' with no NAVER matches. Keep the city
    // and district as well, since multiple cities share neighbourhood names.
    return {
      for (final part in [
        place.administrativeArea,
        place.subAdministrativeArea,
        place.locality,
        place.subLocality,
      ])
        if (part?.trim().isNotEmpty == true) part!.trim(),
    }.join(' ');
  }

  String _positionKey(double lat, double lng) =>
      '${lat.toStringAsFixed(3)}:${lng.toStringAsFixed(3)}';

  T? _cached<T>(Map<String, _CacheEntry<T>> cache, String key) {
    final entry = cache[key];
    if (entry == null) return null;
    if (_now().difference(entry.fetchedAt) >= _cacheTtl) {
      cache.remove(key);
      return null;
    }
    return entry.value;
  }

  void _remember<T>(Map<String, _CacheEntry<T>> cache, String key, T value) {
    cache.removeWhere(
      (_, entry) => _now().difference(entry.fetchedAt) >= _cacheTtl,
    );
    if (!cache.containsKey(key) && cache.length >= _maxCacheEntries) {
      cache.remove(cache.keys.first);
    }
    cache[key] = _CacheEntry(value, _now());
  }

  Future<String> _area(double lat, double lng) {
    final key = _positionKey(lat, lng);
    final cached = _cached(_areas, key);
    if (cached != null) return Future.value(cached);
    return _pendingAreas.putIfAbsent(
      key,
      () => _loadArea(key, lat, lng).whenComplete(() {
        _pendingAreas.remove(key);
      }),
    );
  }

  Future<String> _loadArea(String key, double lat, double lng) async {
    try {
      final area = await _resolveArea(lat, lng).timeout(geocodingTimeout);
      if (area.isNotEmpty) _remember(_areas, key, area);
      return area;
    } catch (_) {
      // Preserve the existing category-only fallback; do not retain a failed
      // geocode so that the next attempt can recover its local query.
      debugPrint('Reverse geocoding unavailable; using category-only search.');
      return '';
    }
  }

  Future<List<FacilityResult>> search({
    required String category,
    required double lat,
    required double lng,
  }) {
    final key = '$category:${_positionKey(lat, lng)}';
    final cached = _cached(_results, key);
    if (cached != null) return Future.value(cached);
    return _pendingSearches.putIfAbsent(
      key,
      () => _search(category, lat, lng).whenComplete(() {
        _pendingSearches.remove(key);
      }),
    );
  }

  Future<List<FacilityResult>> _search(
    String category,
    double lat,
    double lng,
  ) async {
    _checkReady();
    final term = nearbyTerm(category);
    final keyword = term ?? category.trim();
    // Only kind-of-place searches are tied to the neighbourhood; a typed name
    // is looked up nationwide so that distant places can still be found.
    final area = term == null ? '' : await _area(lat, lng);
    // The server answers from Kakao when it can, and otherwise falls back to
    // the NAVER text query below.
    final body = await _post({
      'query': area.isEmpty ? keyword : '$area $keyword',
      'nearby': {
        'keyword': keyword,
        'lat': lat,
        'lng': lng,
        if (_kakaoGroups[keyword] != null) 'group': _kakaoGroups[keyword],
        'mode': term == null ? 'accuracy' : 'nearby',
      },
    });
    if (body['source'] == 'kakao') {
      final places = [
        for (final place in (body['places'] as List).cast<Map>())
          FacilityResult(
            name: place['name'] as String,
            category: place['category'] as String,
            address: place['address'] as String,
            telephone: place['telephone'] as String,
            lat: (place['lat'] as num).toDouble(),
            lng: (place['lng'] as num).toDouble(),
            distanceMeters: Geolocator.distanceBetween(
              lat,
              lng,
              (place['lat'] as num).toDouble(),
              (place['lng'] as num).toDouble(),
            ),
            liveOnly: true,
          ),
      ];
      if (term != null) {
        places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
      }
      // Live-only data is never cached, in line with Kakao's storage terms.
      return List<FacilityResult>.unmodifiable(places);
    }
    final immutable = List<FacilityResult>.unmodifiable(
      _naverResults(body, lat, lng, byDistance: term != null),
    );
    // A failed address lookup should not cache a nationwide fallback for five
    // minutes when a later retry could find the intended neighbourhood.
    // Typed names are nationwide on purpose and may be cached.
    if (term == null || area.isNotEmpty) {
      _remember(_results, '$category:${_positionKey(lat, lng)}', immutable);
    }
    return immutable;
  }

  /// The NAVER place matching a live-only [place], which may be saved, or
  /// [place] itself when it is already storable.
  Future<FacilityResult> findStorable(FacilityResult place) async {
    if (!place.liveOnly) return place;
    _checkReady();
    final district = _district(place.address);
    final body = await _post({
      'query': district.isEmpty ? place.name : '$district ${place.name}',
    });
    final name = _compact(place.name);
    final matches = _naverResults(body, place.lat, place.lng).where((r) {
      final other = _compact(r.name);
      return r.distanceMeters <= 500 &&
          (other.contains(name) || name.contains(other));
    }).toList();
    if (matches.isEmpty) throw const FacilityNotStorableException();
    final match = matches.first;
    return FacilityResult(
      name: match.name,
      category: match.category,
      address: match.address,
      telephone: match.telephone,
      lat: match.lat,
      lng: match.lng,
      distanceMeters: place.distanceMeters,
    );
  }

  void _checkReady() {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const FacilitySearchAuthException();
    }
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw const FacilitySearchNotReadyException();
    }
  }

  List<FacilityResult> _naverResults(
    Map<String, dynamic> body,
    double lat,
    double lng, {
    bool byDistance = true,
  }) {
    final items = (body['items'] as List).cast<Map<String, dynamic>>();
    final results = items.map((item) {
      final itemLng = int.parse(item['mapx'] as String) / 10000000;
      final itemLat = int.parse(item['mapy'] as String) / 10000000;
      return FacilityResult(
        name: _stripTags(item['title'] as String),
        category: item['category'] as String,
        address: (item['roadAddress'] as String).isNotEmpty
            ? item['roadAddress'] as String
            : item['address'] as String,
        telephone: item['telephone'] as String,
        lat: itemLat,
        lng: itemLng,
        distanceMeters: Geolocator.distanceBetween(lat, lng, itemLat, itemLng),
      );
    }).toList();
    if (byDistance) {
      results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    }
    return results;
  }

  Future<Map<String, dynamic>> _post(Map<String, Object?> payload) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const FacilitySearchAuthException();
    }
    final uri = Uri.parse('$supabaseUrl/functions/v1/facility-search');
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abort.future)
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'apikey': supabaseAnonKey,
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode(payload);
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            requestTimeout,
            onTimeout: () {
              abort.complete();
              throw TimeoutException('시설 검색 응답이 지연되고 있습니다.');
            },
          );
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
    if (response.statusCode == 429) throw const FacilityRateLimitException();
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const FacilitySearchAuthException();
    }
    if (response.statusCode == 404) {
      throw const FacilitySearchNotReadyException();
    }
    if (response.statusCode == 503) {
      try {
        final error = jsonDecode(utf8.decode(response.bodyBytes));
        if (error is Map &&
            (error['code'] == 'SEARCH_NOT_CONFIGURED' ||
                error['error'] == '시설 검색을 준비 중입니다.')) {
          throw const FacilitySearchNotReadyException();
        }
      } on FormatException {
        // Non-JSON outage pages are server failures, not setup notices.
      }
    }
    if (response.statusCode != 200) {
      // Server response bodies may contain technical information. Keep the
      // status for diagnosis without displaying the raw body to users.
      throw FacilitySearchServerException(response.statusCode);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  void close() => _client.close();
}

/// See [FacilitySearchService.findStorable].
Future<FacilityResult> findStorableFacility(FacilityResult place) =>
    _searchService.findStorable(place);

Future<List<FacilityResult>> searchNearbyFacilities({
  required String category,
  required double lat,
  required double lng,
}) => _searchService.search(category: category, lat: lat, lng: lng);

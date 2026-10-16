import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const _clientId = String.fromEnvironment('NAVER_SEARCH_CLIENT_ID');
const _clientSecret = String.fromEnvironment('NAVER_SEARCH_CLIENT_SECRET');

/// Thrown when the NAVER API Hub free quota is exhausted (HTTP 429), so
/// callers can show a friendly message instead of a raw error.
class FacilityRateLimitException implements Exception {
  const FacilityRateLimitException();
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
}

String _stripTags(String html) => html.replaceAll(RegExp('<[^>]*>'), '');

/// Keeps the existing API and query format while sharing connections, address
/// lookups and concurrent requests between home and the facility map.
class FacilitySearchService {
  FacilitySearchService({
    http.Client? client,
    Future<String> Function(double lat, double lng)? resolveArea,
    DateTime Function()? now,
    this.geocodingTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _resolveArea = resolveArea ?? _reverseGeocode,
       _now = now ?? DateTime.now;

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
    final placemarks = await Geocoding().placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return '';
    final place = placemarks.first;
    return place.subLocality?.isNotEmpty == true
        ? place.subLocality!
        : (place.locality ?? '');
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
    final area = await _area(lat, lng);
    final uri = Uri.https('naverapihub.apigw.ntruss.com', '/search/v1/local', {
      'query': area.isEmpty ? category : '$area $category',
      'display': '5',
    });
    final abort = Completer<void>();
    final request =
        http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..headers.addAll({
            'X-NCP-APIGW-API-KEY-ID': _clientId,
            'X-NCP-APIGW-API-KEY': _clientSecret,
          });
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
    if (response.statusCode != 200) {
      // Server response bodies may contain technical information. Keep the
      // status for diagnosis without displaying the raw body to users.
      throw http.ClientException('지역검색 API 오류 (${response.statusCode})', uri);
    }
    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
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
    }).toList()..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final immutable = List<FacilityResult>.unmodifiable(results);
    // A failed address lookup should not cache a nationwide fallback for five
    // minutes when a later retry could find the intended neighbourhood.
    if (area.isNotEmpty) {
      _remember(_results, '$category:${_positionKey(lat, lng)}', immutable);
    }
    return immutable;
  }

  void close() => _client.close();
}

Future<List<FacilityResult>> searchNearbyFacilities({
  required String category,
  required double lat,
  required double lng,
}) => _searchService.search(category: category, lat: lat, lng: lng);

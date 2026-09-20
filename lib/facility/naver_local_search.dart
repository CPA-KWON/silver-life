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

class _CacheEntry {
  _CacheEntry(this.results) : fetchedAt = DateTime.now();
  final List<FacilityResult> results;
  final DateTime fetchedAt;
}

final _cache = <String, _CacheEntry>{};
const _cacheTtl = Duration(minutes: 5);

class FacilityResult {
  const FacilityResult({
    required this.name,
    required this.category,
    required this.address,
    required this.telephone,
    required this.lat,
    required this.lng,
    required this.distanceMeters,
  });

  final String name;
  final String category;
  final String address;
  final String telephone;
  final double lat;
  final double lng;
  final double distanceMeters;
}

String _stripTags(String html) => html.replaceAll(RegExp('<[^>]*>'), '');

/// Searches NAVER Local Search for [category] near [lat]/[lng], sorted by
/// straight-line distance. The Local Search API has no geo-radius
/// parameter, so the current location is first reverse-geocoded to a
/// district name (e.g. "강남구") which is prefixed onto the query text to
/// bias results toward that area.
Future<List<FacilityResult>> searchNearbyFacilities({
  required String category,
  required double lat,
  required double lng,
}) async {
  // Round to ~100m so minor GPS jitter still hits the cache.
  final cacheKey =
      '$category:${lat.toStringAsFixed(3)}:${lng.toStringAsFixed(3)}';
  final cached = _cache[cacheKey];
  if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
    return cached.results;
  }

  var areaName = '';
  try {
    final placemarks = await Geocoding().placemarkFromCoordinates(lat, lng);
    if (placemarks.isNotEmpty) {
      final place = placemarks.first;
      areaName = place.subLocality?.isNotEmpty == true
          ? place.subLocality!
          : (place.locality ?? '');
    }
  } catch (e) {
    debugPrint('Reverse geocoding failed: $e');
  }

  final query = areaName.isEmpty ? category : '$areaName $category';
  final uri = Uri.https('naverapihub.apigw.ntruss.com', '/search/v1/local', {
    'query': query,
    'display': '5',
  });

  final response = await http.get(
    uri,
    headers: {
      'X-NCP-APIGW-API-KEY-ID': _clientId,
      'X-NCP-APIGW-API-KEY': _clientSecret,
    },
  );

  if (response.statusCode == 429) {
    throw const FacilityRateLimitException();
  }
  if (response.statusCode != 200) {
    throw Exception('지역검색 API 오류 (${response.statusCode}): ${response.body}');
  }

  final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  final items = (body['items'] as List).cast<Map<String, dynamic>>();

  final results = items.map((item) {
    // mapx/mapy, divided by 10,000,000, are plain WGS84 longitude/latitude.
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

  results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  _cache[cacheKey] = _CacheEntry(results);
  return results;
}

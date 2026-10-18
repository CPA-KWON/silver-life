import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding_platform_interface/geocoding_platform_interface.dart'
    as pi;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silver_life/facility/naver_local_search.dart';

class _Factory extends pi.GeocodingPlatformFactory {
  Locale? requestedLocale;
  @override
  pi.Geocoding createGeocoding(pi.GeocodingCreationParams params) =>
      _Geocoder(params, this);
}

class _Geocoder extends pi.Geocoding {
  _Geocoder(super.params, this.factory) : super.implementation();
  final _Factory factory;
  @override
  Future<List<pi.Placemark>> placemarkFromCoordinates(
    double lat,
    double lng, {
    Locale? locale,
  }) async {
    factory.requestedLocale = locale;
    if (locale != const Locale('ko', 'KR')) {
      return [
        pi.Placemark(
          administrativeArea: 'Seoul',
          locality: 'Jung-gu',
          subLocality: 'Sogong-dong',
        ),
      ];
    }
    return [
      pi.Placemark(
        administrativeArea: '서울특별시',
        locality: '중구',
        subLocality: '소공동',
      ),
    ];
  }
}

void main() {
  test(
    'search uses Korean city district and neighbourhood on an English device',
    () async {
      final factory = _Factory();
      pi.GeocodingPlatformFactory.instance = factory;
      String? query;
      final service = FacilitySearchService(
        supabaseUrl: 'https://test.invalid',
        supabaseAnonKey: 'public-test',
        accessToken: () => 'test-session',
        client: MockClient((request) async {
          query = (jsonDecode(request.body) as Map)['query'];
          return http.Response('{"items":[]}', 200);
        }),
      );
      addTearDown(service.close);
      await service.search(category: '약국', lat: 37.5666, lng: 126.979);
      expect(factory.requestedLocale, const Locale('ko', 'KR'));
      expect(query, '서울특별시 중구 소공동 약국');
    },
  );
}

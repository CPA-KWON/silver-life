import 'package:flutter_test/flutter_test.dart';
import 'package:silver_life/activity/activity_place_match.dart';
import 'package:silver_life/facility/facility_catalog.dart';
import 'package:silver_life/facility/naver_local_search.dart';

FacilityResult place(
  String name,
  String category,
  double distance, {
  double lat = 37.5,
  double lng = 127,
}) => FacilityResult(
  name: name,
  category: category,
  address: '서울',
  telephone: '',
  lat: lat,
  lng: lng,
  distanceMeters: distance,
);

void main() {
  test('all categories retain local places during remote outage', () async {
    final calls = <String>[];
    final result = await searchFacilityCatalog(
      category: '전체',
      lat: 37.5,
      lng: 127,
      local: ({required category, required lat, required lng}) async {
        calls.add(category);
        return [place('동네 경로당', category, 100)];
      },
      remote: ({required category, required lat, required lng}) async {
        calls.add(category);
        throw StateError('offline');
      },
    );
    expect(calls.toSet(), {'병원', '약국', '경로당', '복지관'});
    expect(result.partial, isTrue);
    expect(result.results.single.name, '동네 경로당');
  });
  test(
    'a total search failure offers an error instead of false empty state',
    () {
      expect(
        searchFacilityCatalog(
          category: '약국',
          lat: 37.5,
          lng: 127,
          remote: ({required category, required lat, required lng}) async =>
              throw StateError('offline'),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'search deduplicates coordinates and rejects malformed locations',
    () async {
      final r = await searchFacilityCatalog(
        category: '약국',
        lat: 37.5,
        lng: 127,
        remote: ({required category, required lat, required lng}) async => [
          place('가 약국', category, 200),
          place('가약국', category, 200),
          place('나 약국', category, 40, lat: 37.501),
          place('오류', category, 0, lat: double.nan),
          place('오류2', category, 0, lng: 999),
        ],
      );
      expect(r.results.map((p) => p.name), ['나 약국', '가 약국']);
      expect(r.partial, isFalse);
    },
  );
  test(
    'program links require a matching facility and actual nearby coordinates',
    () {
      bool match(Map<String, dynamic> p) =>
          activityMatchesFacility(p, name: '행복복지관', lat: 37.5, lng: 127);
      expect(
        match({'place_name': '행복복지관', 'lat': 37.5001, 'lng': 127}),
        isTrue,
      );
      expect(match({'place_name': '행복복지관', 'lat': 37.6, 'lng': 127}), isFalse);
      expect(match({'place_name': '다른시설', 'lat': 37.5, 'lng': 127}), isFalse);
      expect(match({'place_name': '행복복지관'}), isFalse);
      expect(
        match({
          'source': 'welfare',
          'place_name': '행복복지관',
          'lat': 37.5,
          'lng': 127,
        }),
        isTrue,
      );
      expect(match({'source': 'welfare', 'place_name': '행복복지관'}), isFalse);
    },
  );
}

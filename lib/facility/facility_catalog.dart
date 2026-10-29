import 'local_facility_search.dart';
import 'naver_local_search.dart';

typedef FacilityQuery = Future<List<FacilityResult>> Function({
  required String category,
  required double lat,
  required double lng,
});

class FacilitySearchBatch {
  const FacilitySearchBatch(this.results, {this.partial = false});
  final List<FacilityResult> results;
  final bool partial;
}

/// Same sources used by the old map. "전체" combines categories without hiding
/// a successful local result just because a remote request failed.
Future<FacilitySearchBatch> searchFacilityCatalog({
  required String category,
  required double lat,
  required double lng,
  FacilityQuery? local,
  FacilityQuery? remote,
}) async {
  final localQuery = local ?? searchOwnFacilities,
      remoteQuery = remote ?? searchNearbyFacilities;
  final types = category == '전체' ? ['병원', '약국', '경로당', '복지관'] : [category];
  Object? firstError;
  final groups = await Future.wait([
    for (final type in types)
      () async {
        try {
          return await (kLocallySourcedCategories.contains(type)
                  ? localQuery
                  : remoteQuery)(category: type, lat: lat, lng: lng)
              .timeout(const Duration(seconds: 12));
        } catch (e) {
          firstError ??= e;
          return <FacilityResult>[];
        }
      }(),
  ]);
  final unique = <String, FacilityResult>{};
  for (final result in groups.expand((g) => g)) {
    if (!result.lat.isFinite ||
        !result.lng.isFinite ||
        result.lat.abs() > 90 ||
        result.lng.abs() > 180) {
      continue;
    }
    final key =
        '${result.name.replaceAll(RegExp(r'\s+'), '')}:${result.lat.toStringAsFixed(4)},${result.lng.toStringAsFixed(4)}';
    unique.putIfAbsent(key, () => result);
  }
  final rows = unique.values.toList()
    ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  if (rows.isEmpty && firstError != null) throw firstError!;
  return FacilitySearchBatch(
    rows.take(100).toList(),
    partial: firstError != null,
  );
}

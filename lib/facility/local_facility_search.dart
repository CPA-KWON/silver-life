import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'naver_local_search.dart';

/// Categories backed by our own imported `facilities` table (official
/// public data) instead of a live NAVER Local Search call. Every result
/// then has a stable [FacilityResult.id] that meetup posts can reliably
/// link to — a live search result has no persistent identity to link
/// against.
const kLocallySourcedCategories = {'경로당'};

// Table has no geo-radius query (plain lat/lng columns, no PostGIS). A
// plain `.eq('category', …)` with no ORDER BY over ~1,600 rows is both
// unordered *and* silently truncated at Supabase's default row cap
// (1000) — nearby rows can easily be missing from that arbitrary subset.
// A lat/lng bounding box (padded well past _maxDistanceMeters) is applied
// server-side first so the fetch is both small and guaranteed to contain
// everything truly within range; the exact circular distance is still
// computed and filtered client-side afterward.
const _maxDistanceMeters = 5000.0;
const _maxResults = 10;
const _boxDegrees = 0.1; // ~11km, safely covers the 5km radius

Future<List<FacilityResult>> searchOwnFacilities({
  required String category,
  required double lat,
  required double lng,
}) async {
  final rows = await Supabase.instance.client
      .from('facilities')
      .select('id, name, address, lat, lng, category, telephone')
      .eq('category', category)
      .gte('lat', lat - _boxDegrees)
      .lte('lat', lat + _boxDegrees)
      .gte('lng', lng - _boxDegrees)
      .lte('lng', lng + _boxDegrees);

  final results = rows.map((row) {
    final rowLat = (row['lat'] as num).toDouble();
    final rowLng = (row['lng'] as num).toDouble();
    return FacilityResult(
      id: row['id'] as String,
      name: row['name'] as String,
      category: row['category'] as String? ?? category,
      address: row['address'] as String,
      telephone: row['telephone'] as String? ?? '',
      lat: rowLat,
      lng: rowLng,
      distanceMeters: Geolocator.distanceBetween(lat, lng, rowLat, rowLng),
    );
  }).where((r) => r.distanceMeters <= _maxDistanceMeters).toList();

  results.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  return results.take(_maxResults).toList();
}

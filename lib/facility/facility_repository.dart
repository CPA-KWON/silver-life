import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/address_region.dart';
import 'naver_local_search.dart';

/// Reuses an existing place without allowing a visitor to overwrite its data.
Future<String> ensureFacility(FacilityResult result) async {
  if (result.id != null) return result.id!;
  final (sido, sigungu) = parseRegionFromAddress(result.address);
  final id = await Supabase.instance.client
      .rpc(
        'ensure_facility',
        params: {
          'data': {
            'name': result.name,
            'address': result.address,
            'lat': result.lat,
            'lng': result.lng,
            'category': result.category,
            'telephone': result.telephone,
            'region_sido': sido,
            'region_sigungu': sigungu,
          },
        },
      )
      .timeout(const Duration(seconds: 10));
  return id as String;
}

/// The signed-in user's favorites, newest first. `favorites` rows are copies
/// without facility_id, so results have no [FacilityResult.id].
Future<List<FacilityResult>> loadFavoriteFacilities({int? limit}) async {
  final client = Supabase.instance.client;
  var query = client
      .from('favorites')
      .select('name,address,telephone,lat,lng,category')
      .eq('user_id', client.auth.currentUser!.id)
      .order('created_at', ascending: false);
  final rows = limit == null ? await query : await query.limit(limit);
  return [
    for (final p in rows)
      FacilityResult(
        name: p['name'] as String,
        address: p['address'] as String? ?? '',
        telephone: p['telephone'] as String? ?? '',
        lat: (p['lat'] as num).toDouble(),
        lng: (p['lng'] as num).toDouble(),
        category: p['category'] as String? ?? '',
        distanceMeters: double.nan,
      ),
  ];
}

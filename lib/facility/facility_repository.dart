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

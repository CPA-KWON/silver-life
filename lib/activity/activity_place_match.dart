import 'package:geolocator/geolocator.dart';

import '../facility/welfare_programs.dart' show facilityNameMatches;

bool activityMatchesFacility(
  Map<String, dynamic> p, {
  required String name,
  required double lat,
  required double lng,
}) {
  final a = p['lat'], b = p['lng'];
  if (a is! num ||
      b is! num ||
      !a.isFinite ||
      !b.isFinite ||
      a.abs() > 90 ||
      b.abs() > 180) {
    return false;
  }
  final matches = p['source'] == 'welfare'
      ? facilityNameMatches(name, '${p['place_name']}')
      : '${p['place_name']}'.trim() == name.trim();
  return matches &&
      Geolocator.distanceBetween(lat, lng, a.toDouble(), b.toDouble()) <= 100;
}

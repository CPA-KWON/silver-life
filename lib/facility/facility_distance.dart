import 'package:geolocator/geolocator.dart';

typedef FacilityPositionLoader = Future<Position?> Function();

/// A search origin/camera center is never a substitute for the user's GPS.
/// Reuses a recent accurate fix and does not prompt for permission in details.
Future<Position?> loadFacilityPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final last = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 1),
      );
      if (last != null &&
          DateTime.now().difference(last.timestamp).abs() <=
              const Duration(minutes: 2) &&
          last.accuracy >= 0 &&
          last.accuracy <= 100) {
        return last;
      }
    } catch (_) {
      // A missing cached fix must not prevent a fresh GPS request.
    }
    final fresh = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)),
    );
    return fresh.accuracy >= 0 &&
            fresh.accuracy <= 100 &&
            DateTime.now().difference(fresh.timestamp).abs() <=
                const Duration(minutes: 2)
        ? fresh
        : null;
  } catch (_) {
    return null;
  }
}

String facilityDistanceLabel(double? meters) {
  if (meters == null || !meters.isFinite || meters < 0) {
    return '현재 위치를 확인하면 거리를 볼 수 있어요';
  }
  final distance = meters < 10
      ? '10m 이내'
      : meters < 1000
      ? '약 ${(meters / 10).round() * 10}m'
      : '약 ${(meters / 1000).toStringAsFixed(1)}km';
  return '현재 위치에서 $distance · 직선거리';
}

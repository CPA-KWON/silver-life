import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';

/// Prevents a late first GPS fix from restarting subscriptions after the map
/// was hidden or disposed. Recent accurate fixes avoid a second cold GPS wait.
class SafeMapLocationTracker extends NDefaultMyLocationTracker {
  SafeMapLocationTracker({this.onLocationUnavailable});

  final void Function()? onLocationUnavailable;
  bool _active = true;
  int _generation = 0;

  void setActive(bool active) {
    _active = active;
    if (!active) _generation++;
  }

  @override
  Future<NLatLng?> startLocationService() async {
    final generation = ++_generation;
    if (!_active) return null;
    try {
      final location = await super.startLocationService();
      return _active && generation == _generation ? location : null;
    } catch (_) {
      if (_active && generation == _generation) onLocationUnavailable?.call();
      return null;
    }
  }

  @override
  Future<NLatLng> getCurrentPositionOnce() async {
    try {
      final last = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 1),
      );
      if (last != null &&
          DateTime.now().difference(last.timestamp).abs() <=
              const Duration(minutes: 2) &&
          last.accuracy <= 100) {
        return NLatLng(last.latitude, last.longitude);
      }
    } catch (_) {
      // A missing cached fix must not prevent requesting a fresh one.
    }
    return super.getCurrentPositionOnce().timeout(const Duration(seconds: 10));
  }

  @override
  Stream<NLatLng> get locationStream {
    final generation = _generation;
    return super.locationStream.where(
      (_) => _active && generation == _generation,
    );
  }

  @override
  Stream<double> get headingStream {
    final generation = _generation;
    return super.headingStream.where(
      (_) => _active && generation == _generation,
    );
  }

  @override
  void disposeLocationService() {
    _generation++;
    super.disposeLocationService();
  }
}

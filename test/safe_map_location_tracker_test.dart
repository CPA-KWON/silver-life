import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:silver_life/facility/safe_map_location_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('NDefaultMyLocationTracker');
  late GeolocatorPlatform original;
  late _CachedLocation geo;
  late Completer<Object?> fix;
  var nativeRequests = 0;

  setUp(() {
    original = GeolocatorPlatform.instance;
    geo = _CachedLocation();
    GeolocatorPlatform.instance = geo;
    fix = Completer<Object?>();
    nativeRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestLocationPermission') return 'granted';
          if (call.method == 'getCurrentPositionOnce') {
            nativeRequests++;
            return fix.future;
          }
          throw UnsupportedError(call.method);
        });
  });
  tearDown(() {
    GeolocatorPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('recent accurate cached fix avoids a cold native GPS request', () async {
    geo.position = position(DateTime.now(), 20);
    final location = await SafeMapLocationTracker().startLocationService();
    expect(location, const NLatLng(37.5, 127));
    expect(nativeRequests, 0);
  });

  for (final inaccurate in [false, true]) {
    test(
      'rejects cached fix (inaccurate=$inaccurate) and requests fresh GPS',
      () async {
        geo.position = position(
          inaccurate
              ? DateTime.now()
              : DateTime.now().subtract(const Duration(hours: 1)),
          inaccurate ? 1500 : 20,
        );
        final pending = SafeMapLocationTracker().startLocationService();
        fix.complete({'lat': 37.6, 'lng': 127.1});
        expect(await pending, const NLatLng(37.6, 127.1));
        expect(nativeRequests, 1);
      },
    );
  }

  test(
    'a late first fix is ignored after hiding or disposing the map',
    () async {
      final tracker = SafeMapLocationTracker();
      final pending = tracker.startLocationService();
      tracker.setActive(false);
      tracker.disposeLocationService();
      fix.complete({'lat': 37.6, 'lng': 127.1});
      expect(await pending, isNull);
      tracker.setActive(true);
      geo.position = position(DateTime.now(), 20);
      expect(await tracker.startLocationService(), const NLatLng(37.5, 127));
    },
  );

  test('hidden map does not start permission or location requests', () async {
    final tracker = SafeMapLocationTracker()..setActive(false);
    expect(await tracker.startLocationService(), isNull);
    expect(nativeRequests, 0);
  });

  testWidgets(
    'GPS timeout reports once and a late fix cannot restart tracking',
    (tester) async {
      var failures = 0;
      final tracker = SafeMapLocationTracker(
        onLocationUnavailable: () => failures++,
      );
      final pending = tracker.startLocationService();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(await pending, isNull);
      expect(failures, 1);
      fix.complete({'lat': 37.6, 'lng': 127.1});
      await tester.pump();
      expect(failures, 1);
    },
  );

  test('cached-location timeout still requests a fresh fix', () async {
    geo.pending = Completer<Position?>();
    final pending = SafeMapLocationTracker().getCurrentPositionOnce();
    fix.complete({'lat': 37.6, 'lng': 127.1});
    try {
      expect(await pending, const NLatLng(37.6, 127.1));
      expect(nativeRequests, 1);
    } finally {
      geo.pending!.complete(null);
    }
  });

  test('location button gets the last fix at once while standing', () async {
    const events = EventChannel('NDefaultMyLocationTracker.locationStream');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(events, null),
    );
    geo.position = position(DateTime.now(), 20);
    final tracker = SafeMapLocationTracker();
    await tracker.startLocationService();
    // The map resubscribes when the button switches noFollow -> follow.
    expect(await tracker.locationStream.first, const NLatLng(37.5, 127));
  });
}

Position position(DateTime timestamp, double accuracy) => Position(
  longitude: 127,
  latitude: 37.5,
  timestamp: timestamp,
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _CachedLocation extends GeolocatorPlatform {
  Position? position;
  Completer<Position?>? pending;
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => pending == null ? position : pending!.future;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:silver_life/core/neighborhood_region.dart';
import 'package:silver_life/core/points.dart';
import 'package:silver_life/attendance/attendance_ads.dart';
import 'package:silver_life/attendance/attendance_controller.dart';
import 'package:silver_life/attendance/attendance_dialog.dart';
import 'package:silver_life/home/home_widgets.dart';
import 'package:silver_life/facility/facility_program_preview.dart';
import 'package:silver_life/facility/naver_local_search.dart';

import 'support/fake_attendance_repository.dart';
import 'support/fake_activity_repository.dart';

class FakeAds extends AttendanceAds {
  AttendanceAdResult result = AttendanceAdResult.completed;
  Completer<AttendanceAdResult>? gate;
  int calls = 0;
  @override
  Future<AttendanceAdOffer> offer({
    required int streak,
    required bool attended,
  }) async => AttendanceAdOffer(
    points: 20,
    remaining: 2,
    enabled: attended,
  );
  @override
  Future<AttendanceAdResult> watch() async {
    calls++;
    return gate == null ? result : gate!.future;
  }
}

void main() {
  test(
    'point denomination scales only currency and preserves purchasing power',
    () {
      expect(pointAmount(1), '100');
      expect(pointAmount(5), '500');
      expect(pointAmount(250), '25,000');
      expect(pointAmount(-50), '-5,000');
      expect(pointAmount(null), '—');
      final r = FakeActivityRepository();
      expect(r.programs.first['fee'], 5001); // KRW must remain KRW.
      expect(1250 ~/ 250, 125000 ~/ 25000);
    },
  );
  test('district comes from an unambiguous Korean province/district pair', () {
    expect(
      NeighborhoodRegionResolver.fromPlacemark(
        const Placemark(administrativeArea: '서울특별시', locality: '동작구'),
      ),
      defaultNeighborhood,
    );
    expect(
      NeighborhoodRegionResolver.fromPlacemark(
        const Placemark(administrativeArea: '부산광역시', locality: '중구'),
      ),
      (sido: '부산광역시', sigungu: '중구'),
    );
    expect(
      NeighborhoodRegionResolver.fromPlacemark(const Placemark(locality: '중구')),
      isNull,
    );
    expect(
      NeighborhoodRegionResolver.fromPlacemark(
        const Placemark(administrativeArea: '서울시', locality: '강남구'),
      ),
      (sido: '서울특별시', sigungu: '강남구'),
    );
  });
  test(
    'missing GPS and geocoder failure fall back without using profile region',
    () async {
      final denied = NeighborhoodRegionResolver(
        positionLoader: () async => null,
      );
      expect(await denied.resolve(), defaultNeighborhood);
      final gps = Position(
        longitude: 126.95,
        latitude: 37.5,
        timestamp: DateTime.now(),
        accuracy: 1,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
      var calls = 0;
      final resolver = NeighborhoodRegionResolver(
        positionLoader: () async {
          calls++;
          return gps;
        },
        geocoder: (_, _) async => [
          const Placemark(administrativeArea: '서울특별시', locality: '강남구'),
        ],
      );
      final rows = await Future.wait([resolver.resolve(), resolver.resolve()]);
      expect(rows.every((r) => r.sigungu == '강남구'), true);
      expect(calls, 1);
      final failed = NeighborhoodRegionResolver(
        positionLoader: () async => gps,
        geocoder: (_, _) async => throw StateError('offline'),
      );
      expect(await failed.resolve(), defaultNeighborhood);
    },
  );
  testWidgets('date points and profile icon share a visual center', (t) async {
    await t.binding.setSurfaceSize(const Size(430, 960));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeader(
            nickname: '테스트',
            onProfile: () {},
            onCalendar: () {},
          ),
        ),
      ),
    );
    final date = t.getCenter(find.byKey(const ValueKey('home-date'))).dy;
    final points = t.getCenter(find.byKey(const ValueKey('home-points'))).dy;
    final profile = t
        .getCenter(find.byKey(const ValueKey('home-profile-icon')))
        .dy;
    expect(date, closeTo(points, 1));
    expect(profile, closeTo(points, 1));
  });
  testWidgets(
    'medical facility hides empty activity blocks but keeps real linked programs',
    (t) async {
      final repo = FakeActivityRepository()..programs.clear();
      const place = FacilityResult(
        name: '우리 병원',
        category: '병원',
        lat: 37.5,
        lng: 127,
        address: '서울',
        telephone: '',
        distanceMeters: 0,
      );
      var browse = false;
      Future<void> show(bool hide) => t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FacilityProgramPreview(
              key: ValueKey(hide),
              place: place,
              repository: repo,
              hideWhenEmpty: hide,
              onOpen: (_) {},
              onList: () {},
              onBrowseAll: () => browse = true,
            ),
          ),
        ),
      );
      await show(true);
      await t.pumpAndSettle();
      expect(find.text('이 시설 프로그램'), findsNothing);
      await show(false);
      await t.pumpAndSettle();
      await t.tap(find.text('전체 프로그램 찾기'));
      expect(browse, true);
      repo.programs.add({
        ...FakeActivityRepository().programs.first,
        'place_name': '우리 병원',
        'lat': 37.5,
        'lng': 127,
      });
      await show(true);
      await t.pumpAndSettle();
      expect(find.text('가벼운 산책'), findsOneWidget);
    },
  );
  testWidgets(
    'ad cancel failure success and quota do not credit a test wallet',
    (t) async {
      final repo = FakeAttendanceRepository();
      await repo.checkIn();
      final c = AttendanceController(repository: repo);
      await c.refresh();
      addTearDown(c.dispose);
      final ads = FakeAds()..result = AttendanceAdResult.cancelled;
      await t.pumpWidget(
        MaterialApp(
          home: AttendanceDialog(controller: c, ads: ads),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('▶ 보기'));
      await t.tap(find.text('▶ 보기'));
      await t.pumpAndSettle();
      expect(find.text('끝까지 봐야 받아요'), findsOneWidget);
      ads.result = AttendanceAdResult.unavailable;
      await t.tap(find.text('▶ 보기'));
      await t.pumpAndSettle();
      expect(find.text('지금은 광고가 없어요'), findsOneWidget);
      ads.result = AttendanceAdResult.completed;
      await t.tap(find.text('▶ 보기'));
      await t.pumpAndSettle();
      expect(find.text('테스트 시청 완료'), findsOneWidget);
      await t.tap(find.text('▶ 보기'));
      await t.pumpAndSettle();
      expect(find.text('오늘은 다 받았어요'), findsOneWidget);
      expect(repo.balance, 1);
      expect(repo.paidCount, 1);
    },
  );
  testWidgets('advertisement in flight rejects repeated taps and close', (
    t,
  ) async {
    final repo = FakeAttendanceRepository();
    await repo.checkIn();
    final c = AttendanceController(repository: repo);
    await c.refresh();
    addTearDown(c.dispose);
    final ads = FakeAds()..gate = Completer<AttendanceAdResult>();
    await t.pumpWidget(
      MaterialApp(
        home: AttendanceDialog(controller: c, ads: ads),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('▶ 보기'));
    await t.tap(find.text('▶ 보기'));
    await t.pump();
    expect(find.text('광고 준비 중'), findsOneWidget);
    expect(ads.calls, 1);
    ads.gate!.complete(AttendanceAdResult.cancelled);
    await t.pumpAndSettle();
    expect(repo.balance, 1);
  });
}

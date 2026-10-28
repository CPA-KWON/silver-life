import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import '../ui/neighborhood_design.dart';
import '../core/map_directions.dart';
import '../core/phone_call.dart';
import '../facility/facility_distance.dart';
import 'activity_repository.dart';

class ActivityMapPage extends StatefulWidget {
  const ActivityMapPage({
    super.key,
    required this.program,
    this.mapPlaceholder,
  });
  final ActivityData program;
  final Widget? mapPlaceholder;
  static bool hasCoordinates(ActivityData p) {
    final lat = p['lat'], lng = p['lng'];
    return lat is num &&
        lng is num &&
        lat.isFinite &&
        lng.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lng >= -180 &&
        lng <= 180;
  }

  @override
  State<ActivityMapPage> createState() => _MapState();
}

class _MapState extends State<ActivityMapPage> {
  Position? gps;
  bool checked = false, ready = false, failed = false;
  int version = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    loadGps();
    startTimer();
  }

  void startTimer() {
    timer?.cancel();
    if (widget.mapPlaceholder == null) {
      timer = Timer(const Duration(seconds: 20), () {
        if (mounted && !ready) setState(() => failed = true);
      });
    }
  }

  Future<void> loadGps() async {
    final p = await loadFacilityPosition();
    if (mounted) {
      setState(() {
        gps = p;
        checked = true;
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = widget.program,
        valid = ActivityMapPage.hasCoordinates(p),
        phone = '${p['telephone'] ?? ''}';
    final distance = valid && gps != null
        ? Geolocator.distanceBetween(
            gps!.latitude,
            gps!.longitude,
            (p['lat'] as num).toDouble(),
            (p['lng'] as num).toDouble(),
          )
        : null;
    return NeighborhoodScreen(
      title: '프로그램 장소',
      tint: neighborhoodAmber,
      child: Column(
        children: [
          Expanded(
            child: !valid
                ? const ActivityEmpty(
                    '장소의 위치 정보가 없어요',
                    message: '아래 주소와 기관 안내를 확인해 주세요.',
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child:
                            widget.mapPlaceholder ??
                            NaverMap(
                              key: ValueKey(version),
                              options: NaverMapViewOptions(
                                initialCameraPosition: NCameraPosition(
                                  target: NLatLng(
                                    (p['lat'] as num).toDouble(),
                                    (p['lng'] as num).toDouble(),
                                  ),
                                  zoom: 16,
                                ),
                                locationButtonEnable: false,
                              ),
                              onMapReady: (controller) async {
                                timer?.cancel();
                                if (mounted) setState(() => ready = true);
                                await controller.addOverlay(
                                  NMarker(
                                    id: 'activity-place',
                                    position: NLatLng(
                                      (p['lat'] as num).toDouble(),
                                      (p['lng'] as num).toDouble(),
                                    ),
                                    caption: NOverlayCaption(
                                      text: '${p['place_name']}',
                                    ),
                                  ),
                                );
                              },
                            ),
                      ),
                      if (failed)
                        Positioned.fill(
                          child: ColoredBox(
                            color: PetColors.background,
                            child: Center(
                              child: ActivityEmpty(
                                '지도를 불러오지 못했어요',
                                message: '시설 주소는 아래에서 확인할 수 있어요.',
                                action: '다시 시도',
                                onAction: () {
                                  setState(() {
                                    ready = false;
                                    failed = false;
                                    version++;
                                  });
                                  startTimer();
                                },
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ActivityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${p['title'] ?? ''}',
                    style: petText(16, color: PetColors.secondary),
                  ),
                  Text('${p['place_name'] ?? ''}', style: petText(23)),
                  if ('${p['address'] ?? ''}'.isNotEmpty)
                    Text(
                      '${p['address']}',
                      style: petText(16, color: PetColors.secondary),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    checked
                        ? facilityDistanceLabel(distance)
                        : '현재 위치에서 거리를 확인하고 있어요',
                    style: petText(15, color: PetColors.secondary),
                  ),
                  if (checked && gps == null)
                    TextButton(
                      onPressed: openAppSettings,
                      child: const Text('휴대폰 위치 설정 열기'),
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (phone.isNotEmpty)
                        ActivityButton(
                          '전화',
                          color: PetColors.green,
                          onTap: () => callFacility(c, phone),
                        ),
                      if (valid)
                        ActivityButton(
                          '길 찾기',
                          icon: Icons.directions_walk,
                          onTap: () => openMapDirections(
                            c,
                            lat: (p['lat'] as num).toDouble(),
                            lng: (p['lng'] as num).toDouble(),
                            name: '${p['place_name']}',
                          ),
                        ),
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('활동 상세로 돌아가기'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

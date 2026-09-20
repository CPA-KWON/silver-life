import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:permission_handler/permission_handler.dart';

/// Minimal map screen: shows the NAVER map centered on the user's current
/// location once granted. Facility markers/category filters come once a
/// facility data source (e.g. public health API, place search API) is chosen.
class FacilitySearchPage extends StatelessWidget {
  const FacilitySearchPage({super.key});

  static const _seoulCityHall = NLatLng(37.5666, 126.979);

  @override
  Widget build(BuildContext context) {
    return NaverMap(
      options: const NaverMapViewOptions(
        initialCameraPosition: NCameraPosition(
          target: _seoulCityHall,
          zoom: 14,
        ),
        locationButtonEnable: true,
      ),
      onMapReady: (controller) async {
        final status = await Permission.location.request();
        if (status.isGranted) {
          controller.setLocationTrackingMode(NLocationTrackingMode.follow);
        }
      },
    );
  }
}

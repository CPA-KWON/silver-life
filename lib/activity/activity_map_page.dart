import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

import 'activity_repository.dart';

/// The program's stored coordinates, independent of facility presence/search.
class ActivityMapPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final position = hasCoordinates(program)
        ? NLatLng(
            (program['lat'] as num).toDouble(),
            (program['lng'] as num).toDouble(),
          )
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('활동 장소 지도')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('${program['title']}\n${program['place_name']}'),
          ),
          Expanded(
            child: position == null
                ? const Center(child: Text('장소의 위치 정보가 없어요. 기관에 문의해주세요.'))
                : mapPlaceholder ??
                      NaverMap(
                        options: NaverMapViewOptions(
                          initialCameraPosition: NCameraPosition(
                            target: position,
                            zoom: 16,
                          ),
                          locationButtonEnable: false,
                        ),
                        onMapReady: (controller) async {
                          final marker = NMarker(
                            id: 'activity-place',
                            position: position,
                            caption: NOverlayCaption(
                              text: '${program['place_name']}',
                            ),
                          );
                          marker.setOnTapListener((_) {
                            if (context.mounted) Navigator.of(context).pop();
                          });
                          await controller.addOverlay(marker);
                        },
                      ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.article_outlined),
              label: const Text('활동 상세로 돌아가기'),
            ),
          ),
        ],
      ),
    );
  }
}

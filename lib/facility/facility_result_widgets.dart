import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../ui/neighborhood_design.dart';
import 'naver_local_search.dart';
import 'facility_distance.dart';

Color facilityColor(String category) => category.contains('약국')
    ? PetColors.green
    : category.contains('경로당')
    ? PetColors.orange
    : category.contains('복지관')
    ? PetColors.purple
    : Colors.redAccent;
IconData facilityIcon(String category) => category.contains('약국')
    ? Icons.medication_outlined
    : category.contains('경로당')
    ? Icons.home_rounded
    : category.contains('복지관')
    ? Icons.favorite
    : Icons.local_hospital;

class FacilityResultTile extends StatelessWidget {
  const FacilityResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.position,
    this.selected = false,
  });
  final FacilityResult result;
  final Position? position;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) {
    final p = position;
    final distance = p == null
        ? null
        : Geolocator.distanceBetween(
            p.latitude,
            p.longitude,
            result.lat,
            result.lng,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ActivityCard(
        padding: 12,
        border: BorderSide(color: selected ? PetColors.blue : PetColors.line),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 48,
              decoration: BoxDecoration(
                color: facilityColor(result.category).withValues(alpha: .1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                facilityIcon(result.category),
                color: facilityColor(result.category),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(result.name, style: petText(18)),
                  Text(
                    result.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: petText(14, color: PetColors.secondary),
                  ),
                  Text(
                    facilityDistanceLabel(distance),
                    style: petText(13, color: PetColors.blue),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: PetColors.secondary),
          ],
        ),
      ),
    );
  }
}

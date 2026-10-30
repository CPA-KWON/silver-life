import 'package:flutter/material.dart';

import '../ui/neighborhood_design.dart';
import '../activity/activity_repository.dart';
import '../activity/activity_program_card.dart';
import '../activity/activity_place_match.dart';
import 'naver_local_search.dart';

class FacilityProgramPreview extends StatefulWidget {
  const FacilityProgramPreview({
    super.key,
    required this.place,
    required this.onOpen,
    required this.onList,
    this.onBrowseAll,
    this.hideWhenEmpty = false,
    this.repository,
  });
  final FacilityResult place;
  final ValueChanged<ActivityData> onOpen;
  final VoidCallback onList;
  final VoidCallback? onBrowseAll;
  final bool hideWhenEmpty;
  final ActivityRepository? repository;
  @override
  State<FacilityProgramPreview> createState() => _PreviewState();
}

class _PreviewState extends State<FacilityProgramPreview> {
  late Future<List<ActivityData>> data = load();
  Future<List<ActivityData>> load() async {
    final d = await (widget.repository ?? ActivityRepository()).home();
    return [
          ...activityRows(d['programs']),
          ...activityRows(d['welfare_programs']),
        ]
        .where(
          (p) => activityMatchesFacility(
            p,
            name: widget.place.name,
            lat: widget.place.lat,
            lng: widget.place.lng,
          ),
        )
        .toList();
  }

  @override
  void didUpdateWidget(covariant FacilityProgramPreview old) {
    super.didUpdateWidget(old);
    if (old.place.name != widget.place.name ||
        old.place.lat != widget.place.lat ||
        old.place.lng != widget.place.lng) {
      data = load();
    }
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<ActivityData>>(
    future: data,
    builder: (c, s) {
      final rows = s.data ?? <ActivityData>[];
      // Medical places focus on visiting. Actual linked programs still appear.
      if (widget.hideWhenEmpty && rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('이 시설 프로그램', style: petText(22))),
              TextButton(
                onPressed: widget.onList,
                child: const Text('모두 보기 ›'),
              ),
            ],
          ),
          if (s.connectionState != ConnectionState.done)
            const ActivityCard(child: LinearProgressIndicator())
          else if (s.hasError)
            ActivityEmpty(
              '프로그램을 불러오지 못했어요',
              action: '다시 시도',
              onAction: () => setState(() => data = load()),
            )
          else if (rows.isEmpty)
            ActivityEmpty(
              '연결된 프로그램이 아직 없어요',
              message: '다른 시설의 프로그램도 살펴보세요.',
              action: widget.onBrowseAll == null ? null : '전체 프로그램 찾기',
              onAction: widget.onBrowseAll,
            )
          else
            for (final p in rows.take(2))
              ActivityListingCard(program: p, onTap: () => widget.onOpen(p)),
        ],
      );
    },
  );
}

import 'package:flutter/material.dart';

import '../pet/pet_design.dart';
import 'activity_design.dart';
import 'activity_repository.dart';

Color activityCategoryColor(String? category) => switch (category) {
  '건강·운동' => const Color(0xFF26915C),
  '배움·디지털' => PetColors.purple,
  '생활·기술' => PetColors.orange,
  '지역·이야기' => ActivityColors.blue,
  _ => PetColors.pink,
};
String activityShortDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return '일정 확인 필요';
  return '${d.month}월 ${d.day}일 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

bool activityCanCancel(ActivityData p, ActivityData e) =>
    ['applied', 'approved'].contains(e['status']) &&
    (DateTime.tryParse('${p['starts_at']}')?.isAfter(DateTime.now()) ?? false);
String activityPreferenceSummary(ActivityData p) =>
    '${p['place_name'] ?? '기준 장소'} · ${p['transport'] ?? '도보'} ${p['radius_km'] ?? 3}km · ${(p['interests'] as List? ?? []).join(', ')}';

class ActivityListingCard extends StatelessWidget {
  const ActivityListingCard({
    super.key,
    required this.program,
    required this.onTap,
    this.label,
    this.recommended = false,
  });
  final ActivityData program;
  final VoidCallback onTap;
  final String? label;
  final bool recommended;
  @override
  Widget build(BuildContext context) {
    final p = program, color = activityCategoryColor(p['category']);
    if (p['source'] == 'welfare') return _welfareCard(p, color);
    final days = DateTime.tryParse('${p['deadline']}')
        ?.difference(DateTime.now())
        .inDays;
    final closed =
        p['status'] != 'open' ||
        !(DateTime.tryParse('${p['deadline']}')?.isAfter(DateTime.now()) ??
            false) ||
        (p['enrolled'] as num? ?? 0) >= (p['capacity'] as num? ?? 1);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ActivityCard(
        padding: 0,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PetPill(
                            p['category'] ?? '',
                            color: color.withValues(alpha: .12),
                            ink: color,
                            fontSize: 13,
                          ),
                          PetPill(
                            closed
                                ? '모집 마감'
                                : days != null && days <= 3
                                ? '마감 임박'
                                : '모집 중',
                            color: days != null && days <= 3
                                ? PetColors.yellow
                                : PetColors.mint,
                            ink: days != null && days <= 3
                                ? PetColors.orange
                                : PetColors.green,
                            fontSize: 13,
                          ),
                          if (p['distance_km'] is num)
                            Text(
                              '${(p['distance_km'] as num).toStringAsFixed(1)}km',
                              style: petText(15, color: ActivityColors.blue),
                            ),
                        ],
                      ),
                      if (label != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          label!,
                          style: petText(15, color: ActivityColors.blue),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        p['title'] ?? '',
                        style: petText(22, weight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p['org_name'] ?? p['place_name'] ?? '',
                        style: petText(17, color: ActivityColors.muted),
                      ),
                      if (recommended) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            PetPill(
                              '관심 분야',
                              color: const Color(0xFFE3F0FD),
                              ink: ActivityColors.blue,
                              fontSize: 14,
                            ),
                            PetPill(
                              [
                                '쉬움',
                                '보통',
                                '도전',
                              ][((p['difficulty'] as num? ?? 1).toInt() - 1)
                                  .clamp(0, 2)],
                              color: const Color(0xFFE3F0FD),
                              ink: ActivityColors.blue,
                              fontSize: 14,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _line(
                        Icons.calendar_month_outlined,
                        '${activityShortDate(p['starts_at'])} 시작',
                      ),
                      _line(
                        Icons.people_outline,
                        '정원 ${p['enrolled'] ?? 0}/${p['capacity'] ?? '?'}명',
                      ),
                      if (p['sponsored'] == true)
                        Text(
                          '기관 후원 · 우선 노출',
                          style: petText(13, color: ActivityColors.muted),
                        ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              activityMoney(p['fee']),
                              style: petText(
                                18,
                                color: p['fee'] == 0
                                    ? PetColors.green
                                    : PetColors.ink,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: ActivityColors.muted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welfareCard(ActivityData p, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ActivityCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              PetPill(
                '${p['category']}',
                color: color.withValues(alpha: .12),
                ink: color,
                fontSize: 13,
              ),
              const PetPill(
                '전화·방문 신청',
                color: PetColors.mint,
                ink: PetColors.green,
                fontSize: 13,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('${p['title']}', style: petText(22, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            '${p['org_name']}',
            style: petText(17, color: ActivityColors.muted),
          ),
          const SizedBox(height: 8),
          _line(Icons.calendar_month_outlined, '${p['display_schedule']}'),
          if ((p['raw_program'] as Map?)?['target'] != null)
            _line(Icons.people_outline, '${p['raw_program']['target']}'),
          if (p['distance_km'] is num)
            _line(
              Icons.near_me_outlined,
              (p['distance_km'] as num) < .1
                  ? '기준 장소에서 100m 이내 · 직선거리'
                  : '기준 장소에서 ${(p['distance_km'] as num).toStringAsFixed(1)}km · 직선거리',
            )
          else
            _line(Icons.near_me_outlined, '기준 장소에서 거리 확인 필요'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(child: Text('${p['display_fee']}', style: petText(18))),
              const Icon(Icons.chevron_right, color: ActivityColors.muted),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '모집 여부는 기관에 확인해 주세요',
            style: petText(14, color: PetColors.secondary),
          ),
        ],
      ),
    ),
  );

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: ActivityColors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: petText(
              16,
              color: PetColors.secondary,
              weight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

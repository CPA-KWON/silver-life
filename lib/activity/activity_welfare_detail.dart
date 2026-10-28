import 'package:flutter/material.dart';

import '../core/phone_call.dart';
import '../pet/pet_design.dart';
import 'activity_design.dart';
import 'activity_map_page.dart';
import 'activity_repository.dart';

/// Institution information is discoverable, but cannot create an app enrollment.
class ActivityWelfareDetailPage extends StatelessWidget {
  const ActivityWelfareDetailPage({super.key, required this.program});
  final ActivityData program;
  @override
  Widget build(BuildContext context) {
    final p = program;
    final raw = Map<String, dynamic>.from(p['raw_program'] as Map? ?? {});
    final phone = '${p['telephone'] ?? ''}'.trim();
    final fields = <String, dynamic>{
      '기관': p['org_name'],
      '분야': p['source_category'],
      '일정': p['display_schedule'],
      '운영 기간': raw['period'],
      '참여 대상': raw['target'],
      '비용': p['display_fee'],
      '장소': raw['place'] ?? p['place_name'],
      '주소': p['address'],
      '신청 방법': raw['how_to_apply'] ?? '기관에 전화하거나 방문해 신청 방법을 확인해 주세요.',
      '전화번호': phone,
      '프로그램 안내': raw['description'],
      '추가 안내': raw['note'],
    };
    return ActivityScreen(
      title: '프로그램 상세',
      bottom: phone.isEmpty
          ? null
          : ActivityButton(
              '기관에 전화 문의',
              icon: Icons.phone_outlined,
              onTap: () => callFacility(context, phone),
            ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: PetPill(
              '전화·방문 신청',
              color: PetColors.mint,
              ink: PetColors.green,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${p['title'] ?? ''}',
            style: petText(28, weight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('기관에서 신청하는 프로그램이에요', style: petText(20)),
                const SizedBox(height: 8),
                Text(
                  '현재 모집 여부와 일정은 기관에 확인해 주세요. 전화·방문 신청은 앱 신청 내역과 참여 보상에 자동 반영되지 않아요.',
                  style: petText(16, color: PetColors.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in fields.entries)
                  if (entry.value != null && '${entry.value}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: petText(15, color: PetColors.secondary),
                          ),
                          const SizedBox(height: 5),
                          Text('${entry.value}', style: petText(18)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (ActivityMapPage.hasCoordinates(p))
            ActivityButton(
              '시설 위치 지도 보기',
              light: true,
              icon: Icons.map_outlined,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ActivityMapPage(program: p)),
              ),
            )
          else
            const ActivityEmpty(
              '시설 위치 확인이 필요해요',
              message: '정확한 지도 위치와 연락처는 기관 안내를 확인해 주세요.',
            ),
          if (phone.isEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '등록된 전화번호가 없어요. 위 신청 방법을 확인해 주세요.',
              style: petText(15, color: PetColors.secondary),
            ),
          ],
        ],
      ),
    );
  }
}

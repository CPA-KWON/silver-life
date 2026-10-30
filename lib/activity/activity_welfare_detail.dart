import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../core/phone_call.dart';
import '../core/public_source.dart';
import '../facility/welfare_program_status.dart';
import 'activity_map_page.dart';
import 'activity_repository.dart';

class ActivityWelfareDetailPage extends StatefulWidget {
  const ActivityWelfareDetailPage({super.key, required this.program});
  final ActivityData program;
  @override
  State<ActivityWelfareDetailPage> createState() => _WelfareDetailState();
}

class _WelfareDetailState extends State<ActivityWelfareDetailPage> {
  bool? favorite;
  bool busy = false, favoriteFailed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final c = Supabase.instance.client;
      final r = await c
          .from('welfare_program_favorites')
          .select('program_key')
          .eq('user_id', c.auth.currentUser!.id)
          .eq('program_key', '${widget.program['id']}');
      if (mounted) {
        setState(() {
          favorite = r.isNotEmpty;
          favoriteFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => favoriteFailed = true);
    }
  }

  Future<void> toggle() async {
    if (busy || favorite == null) return;
    setState(() => busy = true);
    try {
      final c = Supabase.instance.client,
          u = c.auth.currentUser!.id,
          key = '${widget.program['id']}';
      if (favorite == true) {
        await c
            .from('welfare_program_favorites')
            .delete()
            .eq('user_id', u)
            .eq('program_key', key);
      } else {
        await c.from('welfare_program_favorites').upsert({
          'user_id': u,
          'program_key': key,
        }, ignoreDuplicates: true);
      }
      if (mounted) setState(() => favorite = favorite != true);
    } catch (_) {
      if (mounted) await activityFailure(context, title: '관심 프로그램을 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void map() => Navigator.push(
    context,
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => ActivityMapPage(program: widget.program),
    ),
  );
  @override
  Widget build(BuildContext c) {
    final p = widget.program,
        raw = Map<String, dynamic>.from(p['raw_program'] as Map? ?? {}),
        phone = '${p['telephone'] ?? ''}'.trim();
    final source = publicSourceUri(raw['source_url']),
        available = welfareProgramVisible(raw);
    final apply = '${raw['how_to_apply'] ?? ''}',
        visit =
            p['application_method'] == 'visit' ||
            apply.contains('방문') && !apply.contains('전화');
    final fields = <String, dynamic>{
      '대상': raw['target'],
      '비용': p['display_fee'],
      '일정': p['display_schedule'],
      '운영 기간': raw['period'],
      '접수 마감일': raw['registration_ends_on'],
      '준비물': raw['preparations'],
      '모집': raw['capacity'] == null
          ? null
          : '정원 ${raw['capacity']}명 · 모집 여부는 기관 확인',
      '접수 장소': visit ? raw['place'] : null,
    };
    return NeighborhoodScreen(
      title: '프로그램 상세',
      tint: neighborhoodAmber,
      actions: [
        IconButton(
          tooltip: favoriteFailed
              ? '관심 상태 다시 불러오기'
              : favorite == null
              ? '관심 상태 확인 중'
              : favorite == true
              ? '관심 프로그램 해제'
              : '관심 프로그램 저장',
          onPressed: busy
              ? null
              : favoriteFailed
              ? load
              : favorite == null
              ? null
              : toggle,
          icon: favorite == null && !favoriteFailed
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  favoriteFailed
                      ? Icons.refresh
                      : favorite == true
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: PetColors.pink,
                ),
        ),
      ],
      bottom: Row(
        children: [
          Expanded(
            child: ActivityButton(
              '지도',
              light: true,
              icon: Icons.map_outlined,
              onTap: map,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ActivityButton(
              source != null
                  ? '기관 홈페이지 확인'
                  : visit
                  ? '접수 문의'
                  : '전화로 신청 문의',
              icon: source != null ? Icons.open_in_new : Icons.phone_outlined,
              color: PetColors.green,
              onTap: source != null
                  ? () => openPublicSource(c, source)
                  : phone.isEmpty
                  ? null
                  : () => callFacility(c, phone),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          NeighborhoodHero(
            title: '${p['title']}',
            subtitle: '${p['org_name']}',
            color: const Color(0xFFED981B),
            tags: [
              PetPill(
                '${p['category']}',
                color: Colors.white,
                ink: PetColors.green,
                fontSize: 12,
              ),
              PetPill(
                !available
                    ? '모집 마감'
                    : source != null
                    ? '기관 홈페이지 신청'
                    : visit
                    ? '방문 신청'
                    : '전화·방문 신청',
                color: Colors.white,
                ink: PetColors.orange,
                fontSize: 12,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ActivityCard(
            color: const Color(0xFFFFF5E4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  !available
                      ? '현재 접수가 마감된 프로그램이에요'
                      : source != null
                      ? '기관 홈페이지에서 신청해요'
                      : visit
                      ? '이 프로그램은 방문해서 신청해요'
                      : '이 프로그램은 기관에 문의해 신청해요',
                  style: petText(21, color: const Color(0xFF935713)),
                ),
                const SizedBox(height: 8),
                Text(
                  '참여 조건을 확인하고 기관에 접수해 주세요.',
                  style: petText(15, color: PetColors.secondary),
                ),
                const SizedBox(height: 14),
                for (final line
                    in apply.isEmpty
                        ? [
                            visit
                                ? '주민센터나 기관에 방문해 접수해 주세요.'
                                : '전화·방문 접수 방법과 모집 여부를 기관에 확인해 주세요.',
                            '참여 대상과 준비물을 확인해 주세요.',
                            '접수 완료 후 안내한 일정에 참여해 주세요.',
                          ]
                        : [
                            apply,
                            '모집 여부와 대상·준비물을 확인해 주세요.',
                            '접수 완료 후 안내한 일정에 참여해 주세요.',
                          ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: PetColors.orange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line,
                            style: petText(16, color: PetColors.secondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (phone.isNotEmpty)
                  ActivityButton(
                    '기관 문의 $phone',
                    light: true,
                    icon: Icons.phone_outlined,
                    onTap: () => callFacility(c, phone),
                  ),
                if (phone.isEmpty)
                  Text(
                    '등록된 전화번호가 없어요. 아래 접수 방법과 기관 안내를 확인해 주세요.',
                    style: petText(15, color: PetColors.secondary),
                  ),
              ],
            ),
          ),
          const NeighborhoodHeading('한눈에 보기', color: PetColors.orange),
          ActivityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in fields.entries)
                  if (e.value != null && '${e.value}'.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.key,
                            style: petText(14, color: PetColors.secondary),
                          ),
                          const SizedBox(height: 4),
                          Text('${e.value}', style: petText(19)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const NeighborhoodHeading('장소', color: PetColors.orange),
          ActivityCard(
            onTap: map,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.place, color: PetColors.purple, size: 40),
                const SizedBox(height: 12),
                Text('${p['place_name']}', style: petText(20)),
                Text(
                  '${p['address'] ?? raw['place'] ?? ''}',
                  style: petText(16, color: PetColors.secondary),
                ),
                const SizedBox(height: 10),
                ActivityButton('시설 위치 지도 보기', light: true, onTap: map),
              ],
            ),
          ),
          if ('${raw['description'] ?? ''}'.isNotEmpty) ...[
            const NeighborhoodHeading('프로그램 안내', color: PetColors.orange),
            ActivityCard(
              child: Text('${raw['description']}', style: petText(18)),
            ),
          ],
          if ('${raw['note'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 14),
            ActivityCard(
              child: Text(
                '${raw['note']}',
                style: petText(16, color: PetColors.secondary),
              ),
            ),
          ],
          if (source != null) ...[
            const SizedBox(height: 14),
            ActivityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('출처 · 기관 공식 홈페이지', style: petText(17)),
                  Text(
                    source.host,
                    style: petText(14, color: PetColors.secondary),
                  ),
                  if (raw['source_verified_at'] != null)
                    Text(
                      '정보 확인 ${'${raw['source_verified_at']}'.split('T').first} · 잔여석은 원문 확인',
                      style: petText(14, color: PetColors.secondary),
                    ),
                  ActivityButton(
                    '원문에서 모집 상태 확인',
                    light: true,
                    onTap: () => openPublicSource(c, source),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            source != null
                ? '기관 홈페이지에서 접수한 내역은 해당 기관에서 확인해 주세요. 앱 신청 내역·참여 보상에는 자동으로 연결되지 않아요.'
                : '전화·방문으로 접수한 내역은 기관에서 확인해 주세요. 앱 신청 내역에는 표시되지 않아요.',
            style: petText(14, color: PetColors.secondary),
          ),
        ],
      ),
    );
  }
}

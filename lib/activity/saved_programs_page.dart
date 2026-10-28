import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import 'activity_repository.dart';
import 'activity_welfare_catalog.dart';
import 'activity_welfare_detail.dart';
import 'activity_detail_page.dart';
import 'activity_hub_page.dart';

/// Explicitly lists favorites, including closed programs. Does not infer an
/// enrollment, remaining capacity, payment or attendance from a saved item.
Future<List<ActivityData>> loadSavedPrograms() async {
  final c = Supabase.instance.client,
      uid = Supabase.instance.client.auth.currentUser!.id;
  final saved = await c
      .from('activity_program_favorites')
      .select('program_id')
      .eq('user_id', uid);
  final external = await c
      .from('welfare_program_favorites')
      .select('program_key')
      .eq('user_id', uid);
  final rows = <ActivityData>[];
  if (saved.isNotEmpty) {
    final programs = await c
        .from('activity_programs')
        .select(
          'id,title,place_name,starts_at,category,status,application_method',
        )
        .inFilter('id', saved.map((p) => p['program_id']).toList());
    rows.addAll(programs);
    for (final f in saved) {
      if (!programs.any((p) => p['id'] == f['program_id'])) {
        rows.add({
          'id': f['program_id'],
          'title': '현재 볼 수 없는 프로그램',
          'unavailable': true,
        });
      }
    }
  }
  if (external.isNotEmpty) {
    final catalog = await ActivityWelfareCatalog(c).load(null);
    for (final f in external) {
      rows.add(
        catalog.where((p) => p['id'] == f['program_key']).firstOrNull ??
            {
              'id': f['program_key'],
              'source': 'welfare',
              'title': '현재 볼 수 없는 기관 프로그램',
              'unavailable': true,
            },
      );
    }
  }
  return rows;
}

class SavedProgramsPage extends StatefulWidget {
  const SavedProgramsPage({
    super.key,
    this.loader = loadSavedPrograms,
    this.repository,
  });
  final Future<List<ActivityData>> Function() loader;
  final ActivityRepository? repository;
  @override
  State<SavedProgramsPage> createState() => _SavedProgramsState();
}

class _SavedProgramsState extends State<SavedProgramsPage> {
  late Future<List<ActivityData>> data = widget.loader();
  bool busy = false;
  Future<void> reload() async {
    final f = widget.loader();
    setState(() {
      data = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> open(ActivityData p) async {
    if (p['unavailable'] == true) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => p['source'] == 'welfare'
            ? ActivityWelfareDetailPage(program: p)
            : ActivityDetailPage(
                programId: p['id'],
                repository: widget.repository,
              ),
      ),
    );
    if (mounted) await reload();
  }

  Future<void> remove(ActivityData p) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (p['source'] == 'welfare') {
        final c = Supabase.instance.client;
        await c
            .from('welfare_program_favorites')
            .delete()
            .eq('user_id', c.auth.currentUser!.id)
            .eq('program_key', p['id']);
      } else {
        await (widget.repository ?? ActivityRepository()).favorite(
          p['id'],
          false,
        );
      }
      if (mounted) await reload();
    } catch (_) {
      if (mounted) await activityFailure(context, title: '관심 프로그램을 해제하지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '관심 프로그램',
    tint: const Color(0xFFFFE4ED),
    child: FutureBuilder<List<ActivityData>>(
      future: data,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const NeighborhoodLoading();
        }
        if (s.hasError) {
          return ActivityEmpty(
            '저장한 프로그램을 불러오지 못했어요',
            action: '다시 시도',
            onAction: reload,
          );
        }
        if (s.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: ActivityEmpty(
              '아직 관심 프로그램이 없어요',
              message: '프로그램 상세에서 하트를 누르면 여기 모여요.',
              action: '전체 프로그램 보기',
              onAction: () => Navigator.push(
                c,
                MaterialPageRoute(
                  builder: (_) => ActivitySectionPage(
                    section: ActivitySection.programs,
                    repository: widget.repository,
                  ),
                ),
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('${s.data!.length}개의 관심 프로그램', style: petText(18)),
              const SizedBox(height: 14),
              for (final p in s.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: ActivityCard(
                    onTap: p['unavailable'] == true ? null : () => open(p),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${p['title']}', style: petText(21)),
                              const SizedBox(height: 6),
                              if (p['place_name'] != null)
                                Text(
                                  '${p['place_name']}',
                                  style: petText(
                                    16,
                                    color: PetColors.secondary,
                                  ),
                                ),
                              if (p['source'] == 'welfare')
                                Text(
                                  '${p['display_schedule']}',
                                  style: petText(
                                    15,
                                    color: PetColors.secondary,
                                  ),
                                ),
                              if (p['status'] == 'closed')
                                const PetPill('모집 마감'),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: '관심 프로그램 해제',
                          onPressed: busy ? null : () => remove(p),
                          icon: const Icon(
                            Icons.favorite,
                            color: PetColors.pink,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: PetColors.secondary,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

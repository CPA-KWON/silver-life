import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_theme.dart';
import '../core/phone_call.dart';
import '../ui/design_widgets.dart';

/// One row of `welfare_programs` (supabase/welfare_programs.sql): a regular
/// program a welfare center runs, shown for information only — signing up
/// happens by phone/visit, unlike the in-app `activity_programs`.
class WelfareProgram {
  const WelfareProgram({
    required this.facilityName,
    required this.title,
    this.category,
    this.description,
    this.schedule,
    this.target,
    this.period,
    this.howToApply,
    this.fee,
    this.isFree,
    this.capacity,
    this.place,
    this.hours,
    this.note,
  });

  factory WelfareProgram.fromRow(Map<String, dynamic> row) => WelfareProgram(
    facilityName: row['facility_name'] as String,
    title: row['title'] as String,
    category: row['category'] as String?,
    description: row['description'] as String?,
    schedule: row['schedule'] as String?,
    target: row['target'] as String?,
    period: row['period'] as String?,
    howToApply: row['how_to_apply'] as String?,
    fee: row['fee'] as String?,
    isFree: row['is_free'] as bool?,
    capacity: (row['capacity'] as num?)?.toInt(),
    place: row['place'] as String?,
    hours: row['hours'] as String?,
    note: row['note'] as String?,
  );

  final String facilityName;
  final String title;
  final String? category;
  final String? description;
  final String? schedule;
  final String? target;
  final String? period;
  final String? howToApply;
  final String? fee;
  final bool? isFree;
  final int? capacity;
  final String? place;
  final String? hours;
  final String? note;

  static const weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
  static final _weeklyPattern = RegExp(r'^(?:매주\s*)?([월화수목금토일])요일');
  static final _timePattern = RegExp(r'(\d{1,2}:\d{2})\s*~\s*(\d{1,2}:\d{2})');

  /// 1 (월) … 7 (일) when [schedule] is a plain weekly slot such as
  /// "매주 화요일 13:00~13:50" or "수요일 10:00~13:00"; null for monthly,
  /// "상시", "월~금요일 …", or no schedule at all.
  int? get weekday {
    final match = _weeklyPattern.firstMatch(schedule?.trim() ?? '');
    if (match == null) return null;
    return weekdayNames.indexOf(match.group(1)!) + 1;
  }

  /// "13:00~13:50", or null when the schedule has no time range.
  String? get timeRange {
    final match = _timePattern.firstMatch(schedule ?? '');
    return match == null ? null : '${match.group(1)}~${match.group(2)}';
  }

  /// Sort key within a weekday group: minutes since midnight of the start.
  int get startMinutes {
    final range = timeRange;
    if (range == null) return 24 * 60;
    final parts = range.split('~').first.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String? get feeLabel => switch (isFree) {
    true => '무료',
    false => '유료',
    null => null,
  };
}

/// Words that NAVER and the program tables add to or drop from the same
/// center's name (NAVER calls 상도은빛복지관 "상도은빛어르신복지관").
final _fillerWords = RegExp(r'\s+|서울시립|시립|구립|어르신|노인');

String _normalize(String name) => name.replaceAll(_fillerWords, '');

/// Whether a map/search result called [facilityName] is the place a program
/// row belongs to. Names from NAVER can carry extra words (e.g. "서울시립
/// 상도은빛복지관"), so filler words are ignored and either name containing
/// the other counts — but only for reasonably specific names, so a bare
/// "복지관" can't match everything.
@visibleForTesting
bool facilityNameMatches(String facilityName, String programFacilityName) {
  final place = _normalize(facilityName);
  final program = _normalize(programFacilityName);
  if (place.isEmpty || program.isEmpty) return false;
  if (place.contains(program)) return true;
  return place.length >= 5 && program.contains(place);
}

/// The whole table is small (one row per program across a few centers), so
/// it's fetched once and filtered locally; a failed fetch is retried on the
/// next facility opened instead of being cached.
class WelfareProgramRepository {
  static Future<List<WelfareProgram>>? _all;

  static Future<List<WelfareProgram>> programsFor(String facilityName) async {
    final future = _all ??= _fetchAll();
    try {
      final all = await future;
      return all.where((p) => facilityNameMatches(facilityName, p.facilityName)).toList();
    } catch (_) {
      _all = null;
      rethrow;
    }
  }

  static Future<List<WelfareProgram>> _fetchAll() async {
    final rows = await Supabase.instance.client
        .from('welfare_programs')
        .select()
        .order('id')
        .timeout(const Duration(seconds: 10));
    return rows.map(WelfareProgram.fromRow).toList();
  }
}

/// "이 복지관에서 운영 중인 프로그램" card on the facility detail screen,
/// grouped by weekday. Renders nothing for facilities with no programs (or
/// when the fetch fails), so ordinary hospitals/pharmacies are unaffected.
class WelfareProgramsSection extends StatefulWidget {
  const WelfareProgramsSection({
    super.key,
    required this.facilityName,
    this.telephone = '',
  });

  final String facilityName;
  final String telephone;

  @override
  State<WelfareProgramsSection> createState() => _WelfareProgramsSectionState();
}

class _WelfareProgramsSectionState extends State<WelfareProgramsSection> {
  late Future<List<WelfareProgram>> _future = _load();

  Future<List<WelfareProgram>> _load() =>
      WelfareProgramRepository.programsFor(widget.facilityName);

  @override
  void didUpdateWidget(covariant WelfareProgramsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facilityName != widget.facilityName) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WelfareProgram>>(
      future: _future,
      builder: (context, snapshot) {
        final programs = snapshot.data;
        if (programs == null || programs.isEmpty) {
          if (snapshot.hasError) debugPrint('welfare_programs: ${snapshot.error}');
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _ProgramsCard(programs: programs, telephone: widget.telephone),
        );
      },
    );
  }
}

class _ProgramsCard extends StatelessWidget {
  const _ProgramsCard({required this.programs, required this.telephone});

  final List<WelfareProgram> programs;
  final String telephone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final byWeekday = <int, List<WelfareProgram>>{};
    final other = <WelfareProgram>[];
    final unscheduled = <WelfareProgram>[];
    for (final program in programs) {
      final day = program.weekday;
      if (day != null) {
        byWeekday.putIfAbsent(day, () => []).add(program);
      } else if (program.schedule != null) {
        other.add(program);
      } else {
        unscheduled.add(program);
      }
    }
    for (final list in byWeekday.values) {
      list.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    }
    final today = DateTime.now().weekday;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '이 복지관에서 운영 중인 프로그램 (${programs.length}개)',
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '요일을 누르면 프로그램이 보여요. 신청은 복지관에 전화하거나 방문해 주세요.',
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          for (final day in byWeekday.keys.toList()..sort())
            _ProgramGroup(
              title: '${WelfareProgram.weekdayNames[day - 1]}요일',
              badge: day == today ? '오늘' : null,
              programs: byWeekday[day]!,
              initiallyExpanded: day == today,
              telephone: telephone,
            ),
          if (other.isNotEmpty)
            _ProgramGroup(
              title: '매월·상시 프로그램',
              programs: other,
              telephone: telephone,
              showSchedule: true,
            ),
          if (unscheduled.isNotEmpty)
            _ProgramGroup(
              title: '요일 미정 · 복지관 문의',
              programs: unscheduled,
              telephone: telephone,
            ),
        ],
      ),
    );
  }
}

class _ProgramGroup extends StatelessWidget {
  const _ProgramGroup({
    required this.title,
    required this.programs,
    required this.telephone,
    this.badge,
    this.initiallyExpanded = false,
    this.showSchedule = false,
  });

  final String title;
  final String? badge;
  final List<WelfareProgram> programs;
  final String telephone;
  final bool initiallyExpanded;
  final bool showSchedule;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Drops ExpansionTile's default top/bottom divider lines inside the card.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        minTileHeight: 56,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Row(
          children: [
            Flexible(child: Text('$title (${programs.length}개)')),
            if (badge != null) ...[
              const SizedBox(width: 8),
              StatusPill(label: badge!, tone: StatusPillTone.primary),
            ],
          ],
        ),
        children: [
          for (final program in programs)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(program.title),
              subtitle: Text(
                [
                  if (showSchedule) program.schedule else program.timeRange,
                  program.feeLabel,
                ].whereType<String>().join(' · '),
              ),
              trailing: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('자세히'),
                  Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WelfareProgramDetailPage(
                    program: program,
                    telephone: telephone,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class WelfareProgramDetailPage extends StatelessWidget {
  const WelfareProgramDetailPage({
    super.key,
    required this.program,
    this.telephone = '',
  });

  final WelfareProgram program;
  final String telephone;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = <(String, String?)>[
      ('일정', program.schedule ?? '복지관에 문의해 주세요'),
      ('운영 시간', program.hours),
      ('장소', program.place),
      ('대상', program.target),
      ('수강료', program.fee ?? program.feeLabel),
      ('정원', program.capacity == null ? null : '${program.capacity}명'),
      ('신청 방법', program.howToApply ?? '복지관에 전화하거나 방문해 주세요'),
      ('운영 기간', program.period),
      ('내용', program.description),
      ('참고', program.note),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('프로그램 안내')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (program.category != null) ...[
                  TagBadge(label: program.category!),
                  const SizedBox(height: 10),
                ],
                Text(program.title, style: textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(program.facilityName, style: textTheme.bodyMedium),
                for (final (label, value) in rows)
                  if (value != null && value.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(label, style: textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(value, style: textTheme.bodyLarge),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (telephone.isNotEmpty)
            FilledButton.icon(
              onPressed: () => callFacility(context, telephone),
              icon: const Icon(Icons.call),
              label: Text('$telephone 복지관에 전화하기'),
            ),
          const SizedBox(height: 12),
          Text(
            '프로그램 일정은 복지관 사정에 따라 바뀔 수 있어요. 가기 전에 전화로 확인해 주세요.',
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

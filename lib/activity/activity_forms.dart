export 'activity_personal_forms.dart';

import 'package:flutter/material.dart';

import '../facility/facility_search_page.dart';
import '../facility/naver_local_search.dart';
import '../ui/design_widgets.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';

typedef ActivityPlacePicker = Future<FacilityResult?> Function(BuildContext);
Future<FacilityResult?> pickActivityPlace(BuildContext c) =>
    Navigator.of(c).push<FacilityResult>(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, a, b) => const FacilityPickerPage(),
      ),
    );
Future<DateTime?> pickActivityDate(BuildContext c, DateTime? initial) async {
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, now.day);
  final base = initial != null && initial.isAfter(first) ? initial : now;
  final date = await showDatePicker(
    context: c,
    initialDate: base,
    firstDate: first,
    lastDate: DateTime(now.year + 3),
  );
  if (date == null || !c.mounted) return null;
  final time = await showTimePicker(
    context: c,
    initialTime: TimeOfDay.fromDateTime(base),
  );
  return time == null
      ? null
      : DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

Widget activityInput(
  TextEditingController controller,
  String label, {
  bool number = false,
  int lines = 1,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    maxLines: lines,
    keyboardType: number ? TextInputType.number : TextInputType.text,
    validator: (v) => v == null || v.trim().isEmpty ? '$label 입력해주세요' : null,
  ),
);
Widget activitySelect<T>(
  String label,
  T value,
  List<T> values,
  ValueChanged<T> changed, {
  String Function(T)? describe,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: DropdownButtonFormField<T>(
    decoration: InputDecoration(labelText: label),
    initialValue: value,
    isExpanded: true,
    items: [
      for (final v in values)
        DropdownMenuItem(value: v, child: Text(describe?.call(v) ?? '$v')),
    ],
    onChanged: (v) {
      if (v != null) changed(v);
    },
  ),
);

class ActivitySaveForm extends StatefulWidget {
  const ActivitySaveForm({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.enabled = true,
  });
  final String title;
  final List<Widget> children;
  final Future<void> Function() onSave;
  final bool enabled;
  @override
  State<ActivitySaveForm> createState() => _ActivitySaveFormState();
}

class _ActivitySaveFormState extends State<ActivitySaveForm> {
  final form = GlobalKey<FormState>();
  bool busy = false;
  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.onSave();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) activityMessage(context, '저장하지 못했어요. $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy || !widget.enabled ? null : save,
                child: Text(busy ? '저장 중…' : '저장'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ActivityProgramForm extends StatefulWidget {
  const ActivityProgramForm({
    super.key,
    required this.organizations,
    this.repository,
    this.placePicker = pickActivityPlace,
    this.datePicker = pickActivityDate,
    this.initialKind = 'activity',
  });
  final List<ActivityData> organizations;
  final String initialKind;
  final ActivityRepository? repository;
  final ActivityPlacePicker placePicker;
  final Future<DateTime?> Function(BuildContext, DateTime?) datePicker;
  @override
  State<ActivityProgramForm> createState() => _ActivityProgramFormState();
}

class _ActivityProgramFormState extends State<ActivityProgramForm> {
  final title = TextEditingController(),
      description = TextEditingController(),
      targetAudience = TextEditingController(),
      preparations = TextEditingController(),
      floorGuide = TextEditingController(),
      capacity = TextEditingController(text: '10'),
      fee = TextEditingController(text: '0');
  late String? org = widget.organizations.firstOrNull?['id'];
  late String kind = widget.initialKind;
  String category = activityCategories.first, participation = '혼자';
  int level = 1;
  final transports = {'도보', '대중교통', '자동차'};
  FacilityResult? place;
  DateTime? start, end, deadline;
  @override
  void dispose() {
    for (final c in [
      title,
      description,
      capacity,
      fee,
      targetAudience,
      preparations,
      floorGuide,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> chooseDate(String which) async {
    final d = await widget.datePicker(context, switch (which) {
      'start' => start,
      'end' => end,
      _ => deadline,
    });
    if (mounted && d != null) {
      setState(() {
        switch (which) {
          case 'start':
            start = d;
          case 'end':
            end = d;
          default:
            deadline = d;
        }
      });
    }
  }

  Future<void> save() async {
    if (org == null ||
        place == null ||
        start == null ||
        end == null ||
        deadline == null) {
      throw StateError('장소와 모든 일정을 선택해주세요.');
    }
    if (!start!.isAfter(DateTime.now()) ||
        !deadline!.isAfter(DateTime.now()) ||
        !end!.isAfter(start!) ||
        deadline!.isAfter(start!)) {
      throw StateError('모집 마감은 시작 이전, 종료는 시작 이후로 설정해주세요.');
    }
    final n = int.tryParse(capacity.text),
        cost = kind == 'experience' ? 0 : int.tryParse(fee.text);
    if (n == null ||
        n < 1 ||
        n > 1000 ||
        cost == null ||
        cost < 0 ||
        cost > 10000000 ||
        transports.isEmpty) {
      throw StateError('정원·참여비·이동수단을 확인해주세요.');
    }
    await (widget.repository ?? ActivityRepository()).program({
      'org_id': org,
      'title': title.text.trim(),
      'description': description.text.trim(),
      'target_audience': targetAudience.text.trim(),
      'preparations': preparations.text.trim(),
      'floor_guide': floorGuide.text.trim(),
      'kind': kind,
      'category': category,
      'place_name': place!.name,
      'lat': place!.lat,
      'lng': place!.lng,
      'starts_at': start!.toUtc().toIso8601String(),
      'ends_at': end!.toUtc().toIso8601String(),
      'deadline': deadline!.toUtc().toIso8601String(),
      'capacity': n,
      'fee': cost,
      'transports': transports.toList(),
      'participation': participation,
      'difficulty': level,
    });
  }

  @override
  Widget build(BuildContext context) => ActivitySaveForm(
    title: '기관 프로그램 등록',
    enabled: org != null,
    onSave: save,
    children: org == null
        ? [const Text('기관 담당자 권한이 필요해요.')]
        : [
            activitySelect(
              '운영 기관',
              org!,
              [for (final o in widget.organizations) o['id'] as String],
              (v) => setState(() => org = v),
              describe: (v) =>
                  widget.organizations.firstWhere((o) => o['id'] == v)['name'],
            ),
            activitySelect(
              '모집 유형',
              kind,
              ['activity', 'experience'],
              (v) => setState(() => kind = v),
              describe: (v) => v == 'activity' ? '참여 프로그램' : '경험 나눔 도우미 모집',
            ),
            activityInput(title, '프로그램 이름'),
            activityInput(description, '활동 안내', lines: 4),
            for (final field in [
              (targetAudience, '참여 대상'),
              (preparations, '준비물'),
              (floorGuide, '층별 안내'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: field.$1,
                  maxLines: field.$2 == '층별 안내' ? 3 : 1,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: '${field.$2} (선택)'),
                ),
              ),
            activitySelect(
              '활동 분야',
              category,
              activityCategories,
              (v) => setState(() => category = v),
            ),
            OutlinedButton(
              onPressed: () async {
                final p = await widget.placePicker(context);
                if (mounted && p != null) setState(() => place = p);
              },
              child: Text(place?.name ?? '활동 장소 선택'),
            ),
            for (final e in [
              ('start', '활동 시작', start),
              ('end', '활동 종료', end),
              ('deadline', '모집 마감', deadline),
            ])
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: OutlinedButton(
                  onPressed: () => chooseDate(e.$1),
                  child: Text('${e.$2} ${activityDate(e.$3)}'),
                ),
              ),
            const SizedBox(height: 12),
            activityInput(capacity, '정원', number: true),
            if (kind == 'activity') activityInput(fee, '참여비 (원)', number: true),
            const Text(
              '유료 기관 프로그램에는 활성화된 50% 혜택이 적용돼요. 할인 비용 부담은 운영 계약에서 정해주세요. 앱에서 결제하지 않아요.',
            ),
            activitySelect('참여 방식', participation, [
              '혼자',
              '함께',
            ], (v) => setState(() => participation = v)),
            activitySelect<int>('난이도', level, [
              1,
              2,
              3,
            ], (v) => setState(() => level = v)),
            const Text('이용 가능한 이동수단'),
            Wrap(
              spacing: 6,
              children: [
                for (final t in ['도보', '대중교통', '자동차'])
                  FilterChip(
                    label: Text(t),
                    selected: transports.contains(t),
                    onSelected: (v) => setState(() {
                      v ? transports.add(t) : transports.remove(t);
                    }),
                  ),
              ],
            ),
          ],
  );
}

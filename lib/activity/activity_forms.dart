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

class ActivityPreferencesPage extends StatefulWidget {
  const ActivityPreferencesPage({
    super.key,
    this.initial,
    this.repository,
    this.placePicker = pickActivityPlace,
  });
  final ActivityData? initial;
  final ActivityRepository? repository;
  final ActivityPlacePicker placePicker;
  @override
  State<ActivityPreferencesPage> createState() =>
      _ActivityPreferencesPageState();
}

class _ActivityPreferencesPageState extends State<ActivityPreferencesPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Set<String> interests = Set<String>.from(
    widget.initial?['interests'] ?? [activityCategories.first],
  );
  late int radius = widget.initial?['radius_km'] ?? 3,
      minutes = widget.initial?['max_minutes'] ?? 120,
      level = widget.initial?['difficulty'] ?? 1;
  late String transport = widget.initial?['transport'] ?? '도보',
      participation = widget.initial?['participation'] ?? '무관';
  late bool expand = widget.initial?['expand_choices'] ?? true;
  FacilityResult? place;
  Future<void> choose() async {
    final p = await widget.placePicker(context);
    if (mounted && p != null) setState(() => place = p);
  }

  Future<void> save() async {
    if (interests.isEmpty) throw StateError('관심 분야를 선택해주세요.');
    if (place == null && widget.initial == null) {
      throw StateError('기준 장소를 선택해주세요.');
    }
    await repo.preferences({
      'place_name': place?.name ?? widget.initial!['place_name'],
      'lat': place?.lat ?? widget.initial!['lat'],
      'lng': place?.lng ?? widget.initial!['lng'],
      'radius_km': radius,
      'interests': interests.toList(),
      'transport': transport,
      'participation': participation,
      'max_minutes': minutes,
      'difficulty': level,
      'expand_choices': expand,
    });
  }

  @override
  Widget build(BuildContext context) => ActivitySaveForm(
    title: '활동 설정',
    onSave: save,
    children: [
      const Text('내가 편하게 참여할 수 있는 범위를 정해요. 거리는 기준 장소에서의 직선거리예요.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: choose,
        icon: const Icon(Icons.place_outlined),
        label: Text(place?.name ?? widget.initial?['place_name'] ?? '기준 장소 선택'),
      ),
      const SizedBox(height: 12),
      activitySelect<int>(
        '이동 가능 거리',
        radius,
        [1, 3, 5, 10, 20],
        (v) => setState(() => radius = v),
        describe: (v) => '$v km',
      ),
      const Text('관심 분야'),
      Wrap(
        spacing: 6,
        children: [
          for (final c in activityCategories)
            FilterChip(
              label: Text(c),
              selected: interests.contains(c),
              onSelected: (v) => setState(() {
                v ? interests.add(c) : interests.remove(c);
              }),
            ),
        ],
      ),
      const SizedBox(height: 12),
      activitySelect('이동수단', transport, [
        '도보',
        '대중교통',
        '자동차',
      ], (v) => setState(() => transport = v)),
      activitySelect('참여 방식', participation, [
        '무관',
        '혼자',
        '함께',
      ], (v) => setState(() => participation = v)),
      activitySelect<int>(
        '최대 활동시간',
        minutes,
        [30, 60, 120, 240, 480],
        (v) => setState(() => minutes = v),
        describe: (v) => '$v 분',
      ),
      activitySelect<int>(
        '활동 난이도',
        level,
        [1, 2, 3],
        (v) => setState(() => level = v),
        describe: (v) => ['쉬움', '보통', '도전'][v - 1],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('새로운 활동도 만나기'),
        subtitle: const Text('끄면 익숙한 동네 활동을 추천해요. 이동 범위는 자동으로 넓히지 않아요.'),
        value: expand,
        onChanged: (v) => setState(() => expand = v),
      ),
    ],
  );
}

class ActivityExperiencePage extends StatefulWidget {
  const ActivityExperiencePage({
    super.key,
    this.existing,
    this.initialCategory,
    this.repository,
  });
  final ActivityData? existing;
  final String? initialCategory;
  final ActivityRepository? repository;
  @override
  State<ActivityExperiencePage> createState() => _ActivityExperiencePageState();
}

class _ActivityExperiencePageState extends State<ActivityExperiencePage> {
  late final fields = {
    for (final k in [
      'title',
      'description',
      'available_time',
      'preferred_place',
      'activity_type',
    ])
      k: TextEditingController(text: widget.existing?[k] ?? ''),
  };
  late String category =
      widget.existing?['category'] ??
      widget.initialCategory ??
      activityCategories.first;
  late bool active = widget.existing?['active'] ?? true;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ActivitySaveForm(
    title: widget.existing == null ? '나눌 경험 등록' : '나눌 경험 수정',
    onSave: () => (widget.repository ?? ActivityRepository()).experience({
      for (final e in fields.entries) e.key: e.value.text.trim(),
      'category': category,
      'active': active,
    }, id: widget.existing?['id']),
    children: [
      const Text('내 경험은 나만 볼 수 있어요. 모집에 지원하면 해당 기관에 지원 당시의 내용이 전달돼요.'),
      const SizedBox(height: 12),
      activityInput(fields['title']!, '나눌 경험'),
      activitySelect(
        '분야',
        category,
        activityCategories,
        (v) => setState(() => category = v),
      ),
      activityInput(fields['description']!, '경험 설명', lines: 4),
      activityInput(fields['available_time']!, '가능한 시간'),
      activityInput(fields['preferred_place']!, '선호 장소'),
      activityInput(fields['activity_type']!, '활동 형태'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('경험 나눔 참여 가능'),
        value: active,
        onChanged: (v) => setState(() => active = v),
      ),
    ],
  );
}

class ActivityProgramForm extends StatefulWidget {
  const ActivityProgramForm({
    super.key,
    required this.organizations,
    this.repository,
    this.placePicker = pickActivityPlace,
    this.datePicker = pickActivityDate,
  });
  final List<ActivityData> organizations;
  final ActivityRepository? repository;
  final ActivityPlacePicker placePicker;
  final Future<DateTime?> Function(BuildContext, DateTime?) datePicker;
  @override
  State<ActivityProgramForm> createState() => _ActivityProgramFormState();
}

class _ActivityProgramFormState extends State<ActivityProgramForm> {
  final title = TextEditingController(),
      description = TextEditingController(),
      capacity = TextEditingController(text: '10'),
      fee = TextEditingController(text: '0');
  late String? org = widget.organizations.firstOrNull?['id'];
  String kind = 'activity',
      category = activityCategories.first,
      participation = '혼자';
  int level = 1;
  final transports = {'도보', '대중교통', '자동차'};
  FacilityResult? place;
  DateTime? start, end, deadline;
  @override
  void dispose() {
    for (final c in [title, description, capacity, fee]) {
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

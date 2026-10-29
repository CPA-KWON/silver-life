export 'activity_personal_forms.dart';

import 'package:flutter/material.dart';

import '../facility/facility_search_page.dart';
import '../facility/facility_flow.dart';
import '../facility/naver_local_search.dart';
import '../ui/design_widgets.dart';
import 'activity_repository.dart';
import 'activity_widgets.dart';
import '../ui/neighborhood_design.dart';
import '../social/social_form_widgets.dart';

typedef ActivityPlacePicker = Future<FacilityResult?> Function(BuildContext);
Future<FacilityResult?> pickActivityPlace(BuildContext c) =>
    FacilityPickerScope.maybeOf(c)?.call() ??
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
    this.existing,
  });
  final List<ActivityData> organizations;
  final ActivityRepository? repository;
  final ActivityPlacePicker placePicker;
  final Future<DateTime?> Function(BuildContext, DateTime?) datePicker;
  final String initialKind;
  final ActivityData? existing;
  @override
  State<ActivityProgramForm> createState() => _ProgramFormState();
}

class _ProgramFormState extends State<ActivityProgramForm> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      target = TextEditingController(),
      preparations = TextEditingController(),
      floor = TextEditingController(),
      fee = TextEditingController(text: '0'),
      capacity = TextEditingController(text: '20'),
      phone = TextEditingController();
  String? org;
  late String kind = widget.initialKind;
  String category = activityCategories.first,
      method = 'app',
      participation = '함께';
  int level = 1;
  Set<String> transports = {'도보', '대중교통', '자동차'};
  DateTime? start, end, deadline;
  FacilityResult? place;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    org = widget.organizations.firstOrNull?['id'];
    final p = widget.existing;
    if (p != null) {
      org = p['org_id'] ?? org;
      title.text = p['title'] ?? '';
      description.text = p['description'] ?? '';
      target.text = p['target_audience'] ?? '';
      preparations.text = p['preparations'] ?? '';
      floor.text = p['floor_guide'] ?? '';
      fee.text = '${p['fee'] ?? 0}';
      capacity.text = '${p['capacity'] ?? 20}';
      phone.text = p['contact_phone'] ?? '';
      kind = p['kind'] ?? kind;
      category = p['category'] ?? category;
      method = p['application_method'] ?? method;
      participation = p['participation'] ?? participation;
      level = p['difficulty'] ?? level;
      transports = Set<String>.from(p['transports'] ?? transports);
      start = DateTime.tryParse('${p['starts_at']}')?.toLocal();
      end = DateTime.tryParse('${p['ends_at']}')?.toLocal();
      deadline = DateTime.tryParse('${p['deadline']}')?.toLocal();
      if (p['lat'] is num && p['lng'] is num) {
        place = FacilityResult(
          name: p['place_name'] ?? '',
          address: '',
          category: '복지관',
          telephone: p['contact_phone'] ?? '',
          lat: (p['lat'] as num).toDouble(),
          lng: (p['lng'] as num).toDouble(),
          distanceMeters: double.nan,
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      title,
      description,
      target,
      preparations,
      floor,
      fee,
      capacity,
      phone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  ActivityData payload(bool draft) => {
    if (widget.existing?['id'] != null) 'id': widget.existing!['id'],
    if (widget.existing?['draft_id'] != null)
      'draft_id': widget.existing!['draft_id'],
    'org_id': org,
    'title': title.text.trim(),
    'description': description.text.trim(),
    'target_audience': target.text.trim(),
    'preparations': preparations.text.trim(),
    'floor_guide': floor.text.trim(),
    'fee': kind == 'experience' ? 0 : int.tryParse(fee.text),
    'capacity': int.tryParse(capacity.text),
    'kind': kind,
    'category': category,
    'application_method': method,
    'contact_phone': phone.text.trim(),
    'draft': draft,
    'participation': participation,
    'difficulty': level,
    'transports': transports.toList(),
    'place_name': place?.name,
    'lat': place?.lat,
    'lng': place?.lng,
    'starts_at': start?.toUtc().toIso8601String(),
    'ends_at': end?.toUtc().toIso8601String(),
    'deadline': deadline?.toUtc().toIso8601String(),
  };
  Future<void> save({bool draft = false}) async {
    if (busy || org == null) return;
    if (!draft && !form.currentState!.validate()) return;
    if (!draft &&
        (place == null || start == null || end == null || deadline == null)) {
      await activityFailure(context, title: '장소와 모든 일정을 선택해 주세요');
      return;
    }
    if (!draft && (!end!.isAfter(start!) || deadline!.isAfter(start!))) {
      await activityFailure(
        context,
        title: '일정을 확인해 주세요',
        message: '종료는 시작 후, 모집 마감은 시작 전에 정해 주세요.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await (widget.repository ?? ActivityRepository()).program(payload(draft));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '프로그램을 저장하지 못했어요',
          message: '입력 내용을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> date(String key) async {
    final v = await widget.datePicker(
      context,
      key == 'start'
          ? start
          : key == 'end'
          ? end
          : deadline,
    );
    if (v != null && mounted) {
      setState(() {
        if (key == 'start') {
          start = v;
        } else if (key == 'end') {
          end = v;
        } else {
          deadline = v;
        }
      });
    }
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: kind == 'experience'
        ? (widget.existing == null ? '경험 나눔 모집 등록' : '경험 나눔 모집 수정')
        : widget.existing == null
        ? '프로그램 등록'
        : '프로그램 수정',
    tint: const Color(0xFFDDE6F3),
    bottom: Row(
      children: [
        if (widget.existing?['id'] == null) ...[
          Expanded(
            child: ActivityButton(
              '임시 저장',
              light: true,
              onTap: busy ? null : () => save(draft: true),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          flex: 2,
          child: ActivityButton(
            widget.existing == null ? '등록하기' : '수정 저장',
            onTap: busy || org == null ? null : save,
          ),
        ),
      ],
    ),
    child: org == null
        ? const ActivityEmpty('기관 담당자만 등록할 수 있어요', icon: Icons.lock_outline)
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SocialFormCard(
                    '기본 정보',
                    child: Column(
                      children: [
                        activitySelect<String>(
                          '운영 기관',
                          org!,
                          [for (final o in widget.organizations) '${o['id']}'],
                          (v) => setState(() => org = v),
                          describe: (v) =>
                              '${widget.organizations.firstWhere((o) => o['id'] == v)['name']}',
                        ),
                        activityInput(title, '프로그램 이름'),
                        activityInput(description, '활동 안내', lines: 3),
                      ],
                    ),
                  ),
                  SocialFormCard(
                    '분야',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in activityCategories)
                          ChoiceChip(
                            label: Text(v),
                            selected: category == v,
                            onSelected: (_) => setState(() => category = v),
                          ),
                      ],
                    ),
                  ),
                  SocialFormCard(
                    '일정·장소',
                    required: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final v in [
                          ('start', '활동 시작', start),
                          ('end', '활동 종료', end),
                          ('deadline', '모집 마감', deadline),
                        ])
                          OutlinedButton(
                            onPressed: () => date(v.$1),
                            child: Text('${v.$2} ${activityDate(v.$3)}'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final p = await widget.placePicker(c);
                            if (mounted && p != null) setState(() => place = p);
                          },
                          icon: const Icon(Icons.place_outlined),
                          label: Text(place?.name ?? '활동 장소 선택'),
                        ),
                      ],
                    ),
                  ),
                  SocialFormCard(
                    '참여 조건',
                    child: Column(
                      children: [
                        TextField(
                          controller: target,
                          decoration: const InputDecoration(labelText: '대상'),
                        ),
                        const SizedBox(height: 10),
                        if (kind != 'experience')
                          activityInput(fee, '참여비 (원)', number: true)
                        else
                          Text(
                            '경험 나눔은 무료로 참여해요.',
                            style: petText(17, color: PetColors.green),
                          ),
                        TextField(
                          controller: preparations,
                          decoration: const InputDecoration(labelText: '준비물'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: floor,
                          decoration: const InputDecoration(labelText: '층별 안내'),
                          maxLines: 3,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: capacity,
                          decoration: const InputDecoration(labelText: '정원'),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 1000
                                ? '정원은 1~1000명으로 적어 주세요'
                                : null;
                          },
                        ),
                      ],
                    ),
                  ),
                  SocialFormCard(
                    '신청 방법',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final v in [
                              ('app', '앱으로 신청'),
                              ('phone', '전화 신청'),
                              ('visit', '방문 신청'),
                            ])
                              ChoiceChip(
                                label: Text(v.$2),
                                selected: method == v.$1,
                                onSelected: (_) =>
                                    setState(() => method = v.$1),
                              ),
                          ],
                        ),
                        if (method != 'app')
                          TextFormField(
                            controller: phone,
                            decoration: const InputDecoration(
                              labelText: '기관 연락처',
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (v) =>
                                method == 'phone' &&
                                    !RegExp(r'^[+0-9() -]{7,30}$')
                                        .hasMatch(v ?? '')
                                ? '기관 전화번호를 적어 주세요'
                                : null,
                          ),
                        const SizedBox(height: 10),
                        Text(
                          '전화·방문 접수는 앱 신청·참여 보상과 자동 연동되지 않아요.',
                          style: petText(14, color: PetColors.secondary),
                        ),
                      ],
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('추천 세부 조건'),
                    children: [
                      activitySelect(
                        '모집 유형',
                        kind,
                        ['activity', 'experience'],
                        (v) => setState(() => kind = v),
                        describe: (v) =>
                            v == 'activity' ? '참여 프로그램' : '경험 나눔 도우미 모집',
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
                      Wrap(
                        spacing: 8,
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
                  ),
                  SocialFormCard(
                    '참여 보상',
                    child: Text(
                      '앱 신청 프로그램은 기관에서 실제 참여 완료를 확인한 뒤 기존 보상 규칙에 따라 지급돼요.',
                      style: petText(16, color: PetColors.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

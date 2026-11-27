import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../facility/facility_repository.dart';
import '../facility/facility_search_page.dart';
import '../facility/facility_flow.dart';
import '../facility/naver_local_search.dart';
import '../core/meetup_category.dart';
import '../core/terms_gate.dart';
import 'meetup_place_sheet.dart';
import '../ui/neighborhood_design.dart';
import '../app_theme.dart';
import '../ui/design_widgets.dart' show IconBadge;
import '../social/neighborhood_feed.dart' show meetupTopics;
import '../social/social_form_widgets.dart';

class NewMeetupPage extends StatefulWidget {
  const NewMeetupPage({
    super.key,
    this.existingPost,
    this.onFinished,
    this.facilityPicker,
    this.initialFacility,
  });

  /// Pre-fills the place of a new meetup, e.g. when started from a
  /// facility's detail page. Ignored when editing [existingPost].
  final FacilityResult? initialFacility;

  /// When set (id, title, content, event_at, facility), the page edits that
  /// meetup (UPDATE) instead of creating a new one (INSERT). `facility` is
  /// a map with id/name/address/lat/lng/category/telephone, used to
  /// pre-fill the facility picker without a redundant lookup.
  final Map<String, dynamic>? existingPost;
  final ValueChanged<bool>? onFinished;
  final Future<FacilityResult?> Function()? facilityPicker;

  @override
  State<NewMeetupPage> createState() => _NewMeetupPageState();
}

class _NewMeetupPageState extends State<NewMeetupPage> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.existingPost?['title'] as String?,
  );
  late final _contentController = TextEditingController(
    text: widget.existingPost?['content'] as String?,
  );
  bool _isSaving = false;
  late String _topic =
      widget.existingPost?['meetup_topic'] ?? meetupTopics.first;
  late int _capacity =
      widget.existingPost?['max_participants'] ?? kDefaultMaxParticipants;
  late int _duration = widget.existingPost?['duration_minutes'] ?? 60;

  late DateTime? _eventDate = _initialEventAt?.toLocal();
  // Picked with three select boxes: 오전/오후, 1–12시, 10-minute steps.
  late final TimeOfDay? _initialTime = _initialEventAt == null
      ? null
      : TimeOfDay.fromDateTime(_initialEventAt!.toLocal());
  late bool? _isPm = _initialTime == null ? null : _initialTime.hour >= 12;
  late int? _hour12 = _initialTime == null
      ? null
      : (_initialTime.hour % 12 == 0 ? 12 : _initialTime.hour % 12);
  late int? _minute = _initialTime?.minute;

  /// Null until 오전/오후, 시 and 분 are all chosen.
  TimeOfDay? get _eventTime =>
      _isPm == null || _hour12 == null || _minute == null
      ? null
      : TimeOfDay(hour: _hour12! % 12 + (_isPm! ? 12 : 0), minute: _minute!);
  late FacilityResult? _eventFacility = _initialFacility;

  void _finish(bool changed) {
    if (widget.onFinished != null) {
      widget.onFinished!(changed);
    } else {
      Navigator.of(context).pop(changed);
    }
  }

  bool get _isEditing => widget.existingPost != null;

  DateTime? get _initialEventAt {
    final iso = widget.existingPost?['event_at'] as String?;
    return iso == null ? null : DateTime.parse(iso);
  }

  FacilityResult? get _initialFacility {
    if (widget.existingPost == null) return widget.initialFacility;
    final facility = widget.existingPost?['facility'] as Map<String, dynamic>?;
    if (facility == null) return null;
    return FacilityResult(
      id: facility['id'] as String?,
      name: facility['name'] as String,
      category: facility['category'] as String? ?? '',
      address: facility['address'] as String? ?? '',
      telephone: facility['telephone'] as String? ?? '',
      lat: (facility['lat'] as num).toDouble(),
      lng: (facility['lng'] as num).toDouble(),
      distanceMeters: 0,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickSocialDate(context, _eventDate);
    if (mounted && picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickFacility() async {
    // Favorites first; "지도에서 장소 찾기" falls through to the map picker.
    final choice = await showMeetupPlaceSheet(context);
    if (!mounted || choice == null) return;
    if (choice.favorite != null) {
      setState(() => _eventFacility = choice.favorite);
      return;
    }
    // No transition animation: FacilityPickerPage contains a NaverMap
    // (native PlatformView), and animating it in/out during a route
    // transition is known to corrupt Flutter's render tree.
    final mapPicker =
        widget.facilityPicker ?? FacilityPickerScope.maybeOf(context);
    final picked = mapPicker != null
        ? await mapPicker()
        : await Navigator.of(context).push<FacilityResult>(
            PageRouteBuilder<FacilityResult>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const FacilityPickerPage(),
            ),
          );
    if (mounted && picked != null) setState(() => _eventFacility = picked);
  }

  Future<void> _submit() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    if (_eventDate == null || _eventTime == null || _eventFacility == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('모임 날짜·시간·장소를 모두 선택해주세요.')),
        );
      return;
    }

    final selected = DateTime(
      _eventDate!.year,
      _eventDate!.month,
      _eventDate!.day,
      _eventTime!.hour,
      _eventTime!.minute,
    );
    if (selected.isBefore(DateTime.now()) &&
        (!_isEditing || selected.toUtc() != _initialEventAt!.toUtc())) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('미래의 모임 시간을 선택해주세요.')));
      return;
    }
    if (!_isEditing && !await ensureTermsAccepted(context)) return;
    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser!.id;
      final facility = _eventFacility!;

      // Reuse the id we already have (from our own facilities table via
      // FacilityPickerPage) instead of a redundant upsert — one less
      // network round trip, and one less way the id could ever mismatch.
      final String facilityId;
      if (facility.id != null) {
        facilityId = facility.id!;
      } else {
        facilityId = await ensureFacility(facility);
      }

      final date = _eventDate!;
      final time = _eventTime!;
      // Built from local picker values (device timezone) — .toUtc() before
      // serializing so Postgres (which assumes UTC for an offset-less
      // string) stores the instant the user actually picked, not that
      // wall-clock time relabeled as UTC.
      final eventAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );

      final data = {
        'category': kMeetupCategory,
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'event_at': eventAt.toUtc().toIso8601String(),
        'facility_id': facilityId,
        'meetup_topic': _topic,
        'max_participants': _capacity,
        'duration_minutes': _duration,
      };
      if (_isEditing) {
        final updated = await client
            .from('posts')
            .update(data)
            .eq('id', widget.existingPost!['id'] as String)
            .select('id');
        if (updated.isEmpty) throw StateError('모임 수정 권한이 없어요.');
      } else {
        await client.from('posts').insert({...data, 'author_id': userId});
      }
      if (mounted) _finish(true);
    } catch (e) {
      if (mounted) {
        final action = _isEditing ? '수정' : '등록';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('모임 $action에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _cancelMeetup() async {
    if (!await activityDialog(
      context,
      title: '모임을 취소할까요?',
      message: '모집이 종료되고 참여자 화면에도 취소 상태가 표시돼요.',
      action: '모임 취소하기',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client
          .from('posts')
          .update({'meetup_cancelled': true})
          .eq('id', widget.existingPost!['id']);
      if (mounted) _finish(true);
    } catch (_) {
      if (mounted) await activityFailure(context, title: '모임을 취소하지 못했어요');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => NeighborhoodScreen(
    title: _isEditing ? '모임 수정' : '모임 만들기',
    onBack: () => _finish(false),
    bottom: ActivityButton(
      _isEditing ? '수정 저장하기' : '모임 올리기',
      onTap: _isSaving ? null : _submit,
    ),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SocialFormCard(
              '언제, 어디서',
              required: true,
              child: Column(
                children: [
                  _PickerRow(
                    icon: Icons.calendar_today_outlined,
                    label: '날짜',
                    value: _eventDate == null
                        ? '날짜를 골라 주세요'
                        : '${_eventDate!.month}월 ${_eventDate!.day}일',
                    hasValue: _eventDate != null,
                    onTap: _pickDate,
                  ),
                  _TimeSelects(
                    isPm: _isPm,
                    hour: _hour12,
                    minute: _minute,
                    enabled: !_isSaving,
                    onPeriod: (v) => setState(() => _isPm = v),
                    onHour: (v) => setState(() => _hour12 = v),
                    onMinute: (v) => setState(() => _minute = v),
                  ),
                  _PickerRow(
                    icon: Icons.place_outlined,
                    label: '장소',
                    value: _eventFacility?.name ?? '장소를 골라 주세요',
                    hasValue: _eventFacility != null,
                    onTap: _pickFacility,
                  ),
                ],
              ),
            ),
            SocialFormCard(
              '어떤 모임',
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final v in meetupTopics)
                    ChoiceChip(
                      label: Text(v),
                      selected: _topic == v,
                      onSelected: (_) => setState(() => _topic = v),
                    ),
                ],
              ),
            ),
            SocialFormCard(
              '모집 인원',
              required: true,
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final n in {2, 4, 6, 10, _capacity}.toList()..sort())
                    ChoiceChip(
                      label: Text('$n명'),
                      selected: _capacity == n,
                      onSelected: (_) => setState(() => _capacity = n),
                    ),
                ],
              ),
            ),
            SocialFormCard(
              '다른 인원 고르기',
              child: DropdownButtonFormField<int>(
                key: const Key('meetup-capacity'),
                initialValue: _capacity,
                // Same height limit as the time selects; 2–30명 scrolls.
                menuMaxHeight: 300,
                decoration: const InputDecoration(labelText: '최대 인원'),
                items: [
                  for (var n = 2; n <= 30; n++)
                    DropdownMenuItem(value: n, child: Text('$n명')),
                ],
                onChanged: _isSaving
                    ? null
                    : (v) => setState(() => _capacity = v!),
              ),
            ),
            SocialFormCard(
              '함께할 시간',
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final n in {30, 60, 90, 120, _duration}.toList()..sort())
                    ChoiceChip(
                      label: Text('$n분'),
                      selected: _duration == n,
                      onSelected: (_) => setState(() => _duration = n),
                    ),
                ],
              ),
            ),
            SocialFormCard(
              '모임 제목',
              required: true,
              child: TextFormField(
                controller: _titleController,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '제목',
                  hintText: '어떤 모임인지 한눈에 알게 써 주세요',
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '모임 제목을 써 주세요' : null,
              ),
            ),
            SocialFormCard(
              '내용',
              required: true,
              child: TextFormField(
                controller: _contentController,
                maxLength: 1000,
                minLines: 5,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: '내용',
                  hintText: '무엇을 하는지, 준비물이 있는지 알려 주세요',
                ),
                validator: (v) =>
                    (v?.trim().length ?? 0) < 5 ? '내용을 5자 이상 써 주세요' : null,
              ),
            ),
            if (_isEditing)
              TextButton(
                onPressed: _isSaving ? null : _cancelMeetup,
                child: const Text(
                  '모임 취소하기',
                  style: TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Start time as three select boxes side by side (stacked when the screen is
/// narrow or the text is enlarged): 오전/오후, 1–12시, 0–50분 in 10-minute
/// steps. An edited meetup's odd minute (e.g. 15분) stays selectable.
class _TimeSelects extends StatelessWidget {
  const _TimeSelects({
    required this.isPm,
    required this.hour,
    required this.minute,
    required this.enabled,
    required this.onPeriod,
    required this.onHour,
    required this.onMinute,
  });

  final bool? isPm;
  final int? hour;
  final int? minute;
  final bool enabled;
  final ValueChanged<bool?> onPeriod;
  final ValueChanged<int?> onHour;
  final ValueChanged<int?> onMinute;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final itemStyle = textTheme.bodyLarge?.copyWith(
      fontSize: 18,
      color: AppColors.textPrimary,
    );
    Widget select<T>(
      String key,
      String hint,
      T? value,
      List<(T, String)> options,
      ValueChanged<T?> onChanged,
    ) => DropdownButtonFormField<T>(
      key: Key(key),
      initialValue: value,
      isExpanded: true,
      // About five rows, then the list scrolls (the 12 hours otherwise
      // open as a near full-screen list).
      menuMaxHeight: 300,
      style: itemStyle,
      decoration: InputDecoration(labelText: hint),
      items: [
        for (final (v, label) in options)
          DropdownMenuItem(value: v, child: Text(label)),
      ],
      onChanged: enabled ? onChanged : null,
    );
    final minutes = {0, 10, 20, 30, 40, 50, ?minute}.toList()..sort();
    final boxes = [
      select<bool>('meetup-period', '오전/오후', isPm, const [
        (false, '오전'),
        (true, '오후'),
      ], onPeriod),
      select<int>('meetup-hour', '시', hour, [
        for (var h = 1; h <= 12; h++) (h, '$h시'),
      ], onHour),
      select<int>('meetup-minute', '분', minute, [
        for (final m in minutes) (m, '$m분'),
      ], onMinute),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const IconBadge(icon: Icons.schedule, size: 40),
              const SizedBox(width: 12),
              Text(
                '시간',
                style: textTheme.bodyLarge?.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (c, b) {
              final stacked =
                  b.maxWidth < 330 || MediaQuery.textScalerOf(c).scale(1) > 1.3;
              if (stacked) {
                return Column(
                  children: [
                    for (final (i, box) in boxes.indexed) ...[
                      if (i > 0) const SizedBox(height: 10),
                      box,
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (final (i, box) in boxes.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(flex: i == 0 ? 5 : 4, child: box),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.hasValue,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool hasValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconBadge(icon: icon, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: textTheme.bodyLarge?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        value,
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: hasValue
                              ? AppColors.scheduleText
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

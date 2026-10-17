import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/address_region.dart';
import '../facility/facility_search_page.dart';
import '../facility/naver_local_search.dart';
import '../core/meetup_category.dart';
import '../ui/design_widgets.dart';
import '../app_theme.dart';

class NewMeetupPage extends StatefulWidget {
  const NewMeetupPage({
    super.key,
    this.existingPost,
    this.onFinished,
    this.facilityPicker,
  });

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

  late DateTime? _eventDate = _initialEventAt?.toLocal();
  late TimeOfDay? _eventTime = _initialEventAt == null
      ? null
      : TimeOfDay.fromDateTime(_initialEventAt!.toLocal());
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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate != null && _eventDate!.isAfter(now)
          ? _eventDate!
          : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (mounted && picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _eventTime ?? TimeOfDay.now(),
    );
    if (mounted && picked != null) setState(() => _eventTime = picked);
  }

  Future<void> _pickFacility() async {
    // No transition animation: FacilityPickerPage contains a NaverMap
    // (native PlatformView), and animating it in/out during a route
    // transition is known to corrupt Flutter's render tree.
    final picked = widget.facilityPicker != null
        ? await widget.facilityPicker!()
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
        final (sido, sigungu) = parseRegionFromAddress(facility.address);
        final facilityRow = await client
            .from('facilities')
            .upsert({
              'name': facility.name,
              'address': facility.address,
              'lat': facility.lat,
              'lng': facility.lng,
              'category': facility.category,
              'telephone': facility.telephone,
              'region_sido': sido,
              'region_sigungu': sigungu,
            }, onConflict: 'name,address')
            .select('id')
            .single();
        facilityId = facilityRow['id'] as String;
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
      };
      if (_isEditing) {
        await client
            .from('posts')
            .update(data)
            .eq('id', widget.existingPost!['id'] as String);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => _finish(false)),
        title: Text(_isEditing ? '모임 수정' : '모임 만들기'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PickerRow(
                icon: Icons.calendar_today_outlined,
                label: '날짜',
                value: _eventDate == null
                    ? '날짜 선택'
                    : '${_eventDate!.year}.${_eventDate!.month}.${_eventDate!.day}',
                hasValue: _eventDate != null,
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              _PickerRow(
                icon: Icons.access_time,
                label: '시간',
                value: _eventTime == null
                    ? '시간 선택'
                    : _eventTime!.format(context),
                hasValue: _eventTime != null,
                onTap: _pickTime,
              ),
              const SizedBox(height: 8),
              _PickerRow(
                icon: Icons.place_outlined,
                label: '장소',
                value: _eventFacility == null ? '장소 선택' : _eventFacility!.name,
                hasValue: _eventFacility != null,
                onTap: _pickFacility,
              ),
              const SizedBox(height: 12),
              SectionCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(labelText: '모임 제목'),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? '제목을 입력해주세요'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _contentController,
                      decoration: const InputDecoration(labelText: '내용'),
                      maxLines: 8,
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? '내용을 입력해주세요'
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _isSaving ? null : _submit,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditing ? '수정하기' : '등록하기'),
              ),
            ],
          ),
        ),
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
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        value,
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
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

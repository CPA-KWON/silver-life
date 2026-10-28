import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../facility/naver_local_search.dart';
import '../pet/pet_design.dart';
import 'activity_design.dart';
import 'activity_forms.dart' show ActivityPlacePicker, pickActivityPlace;
import 'activity_repository.dart';

class ActivityFormSection extends StatelessWidget {
  const ActivityFormSection({
    super.key,
    required this.number,
    required this.title,
    required this.child,
    this.required = false,
    this.pink = false,
    this.error,
  });
  final int number;
  final String title;
  final Widget child;
  final bool required, pink;
  final String? error;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: ActivityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: pink ? PetColors.pink : ActivityColors.blue,
                child: Text('$number', style: petText(14, color: Colors.white)),
              ),
              Text(title, style: petText(20)),
              if (required)
                Text('*필수', style: petText(14, color: const Color(0xFFD53F34))),
            ],
          ),
          const SizedBox(height: 14),
          child,
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: petText(14, color: const Color(0xFFC83D35)),
              ),
            ),
        ],
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
  State<ActivityPreferencesPage> createState() => _PreferencesState();
}

class _PreferencesState extends State<ActivityPreferencesPage> {
  late Set<String> interests = Set<String>.from(
    widget.initial?['interests'] ?? <String>[],
  );
  late int radius = widget.initial?['radius_km'] ?? 3,
      minutes = widget.initial?['max_minutes'] ?? 120,
      level = widget.initial?['difficulty'] ?? 1;
  late String transport = widget.initial?['transport'] ?? '도보',
      participation = widget.initial?['participation'] ?? '무관';
  late bool expand = widget.initial?['expand_choices'] ?? true;
  FacilityResult? place;
  bool busy = false,
      attempted = false,
      locationTouched = false,
      interestsTouched = false;
  String? locationError;
  String? get name => place?.name ?? widget.initial?['place_name'];
  bool get valid => name != null && interests.isNotEmpty;
  Future<void> choose() async {
    setState(() => locationTouched = true);
    FacilityResult? picked;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('기준 장소 고르기', style: petText(24)),
              const SizedBox(height: 8),
              Text(
                '추천 거리를 재는 출발점이에요',
                style: petText(16, color: PetColors.secondary),
              ),
              const SizedBox(height: 18),
              if (name != null)
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(name!),
                  subtitle: const Text('현재 기준 장소'),
                  onTap: () => Navigator.pop(c),
                ),
              ListTile(
                leading: const Icon(
                  Icons.my_location,
                  color: ActivityColors.blue,
                ),
                title: const Text('지금 내 위치'),
                subtitle: const Text('위치 권한이 필요해요'),
                onTap: () {
                  Navigator.pop(c);
                  locationError = 'current';
                },
              ),
              const SizedBox(height: 10),
              ActivityButton(
                '지도에서 장소 찾기',
                icon: Icons.map_outlined,
                onTap: () {
                  locationError = 'picker';
                  Navigator.pop(c);
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (locationError == 'picker') {
      locationError = null;
      picked = await widget.placePicker(context);
    } else if (locationError == 'current') {
      locationError = null;
      try {
        if (!await Geolocator.isLocationServiceEnabled()) {
          throw StateError('location');
        }
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw StateError('permission');
        }
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            timeLimit: Duration(seconds: 15),
          ),
        );
        picked = FacilityResult(
          name: '지금 내 위치',
          category: '현재 위치',
          address: '',
          telephone: '',
          lat: p.latitude,
          lng: p.longitude,
          distanceMeters: 0,
        );
      } catch (_) {
        if (mounted) {
          await activityFailure(
            context,
            title: '현재 위치를 확인하지 못했어요',
            message: '위치 권한과 휴대폰의 위치 설정을 확인하거나 지도에서 장소를 골라 주세요.',
          );
        }
      }
    }
    if (mounted && picked != null) setState(() => place = picked);
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => attempted = true);
    if (!valid) return;
    setState(() => busy = true);
    try {
      await (widget.repository ?? ActivityRepository()).preferences({
        'place_name': name,
        'lat': place?.lat ?? widget.initial?['lat'],
        'lng': place?.lng ?? widget.initial?['lng'],
        'radius_km': radius,
        'interests': interests.toList(),
        'transport': transport,
        'participation': participation,
        'max_minutes': minutes,
        'difficulty': level,
        'expand_choices': expand,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        await activityFailure(context, title: '조건을 저장하지 못했어요', onRetry: save);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ActivityScreen(
      title: '추천 조건 설정',
      wallet: false,
      bottom: ActivityButton(
        busy
            ? '저장 중…'
            : valid
            ? '저장하고 추천 보기'
            : '필수 항목을 골라 주세요',
        onTap: busy || !valid ? null : save,
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Text(
            '편하게 참여할 수 있는 범위를 정해요. * 표시는 꼭 골라 주세요.',
            style: petText(16, color: PetColors.secondary),
          ),
          const ActivityHeading('어디서, 얼마나 멀리'),
          ActivityFormSection(
            number: 1,
            title: '기준 장소',
            required: true,
            error: (attempted || locationTouched) && name == null
                ? '기준 장소를 골라 주세요'
                : null,
            child: InkWell(
              onTap: choose,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7FC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: attempted && name == null
                        ? Colors.redAccent
                        : const Color(0xFFCCDFEF),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: ActivityColors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name ?? '기준 장소를 골라 주세요',
                        style: petText(17, color: PetColors.secondary),
                      ),
                    ),
                    Text(
                      name == null ? '선택' : '변경',
                      style: petText(16, color: ActivityColors.blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ActivityFormSection(
            number: 2,
            title: '이동 가능 거리',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '기준 장소에서 직선거리예요',
                  style: petText(15, color: PetColors.secondary),
                ),
                const SizedBox(height: 12),
                ActivityChoices<int>(
                  values: const [1, 3, 5, 10, 20],
                  selected: (v) => radius == v,
                  describe: (v) => '${v}km',
                  onSelect: (v) => setState(() => radius = v),
                ),
              ],
            ),
          ),
          ActivityFormSection(
            number: 3,
            title: '이동 수단',
            child: ActivityChoices<String>(
              values: const ['도보', '대중교통', '자동차'],
              selected: (v) => transport == v,
              icons: const {
                '도보': Icons.directions_walk,
                '대중교통': Icons.directions_bus_outlined,
                '자동차': Icons.directions_car_outlined,
              },
              onSelect: (v) => setState(() => transport = v),
            ),
          ),
          const ActivityHeading('어떤 활동을'),
          ActivityFormSection(
            number: 4,
            title: '관심 분야',
            required: true,
            error: (attempted || interestsTouched) && interests.isEmpty
                ? '관심 분야를 하나 이상 골라 주세요'
                : null,
            child: ActivityChoices<String>(
              values: activityCategories,
              selected: interests.contains,
              onSelect: (v) => setState(() {
                interests.contains(v) ? interests.remove(v) : interests.add(v);
              }),
            ),
          ),
          ActivityFormSection(
            number: 5,
            title: '참여 방식',
            child: ActivityChoices<String>(
              values: const ['혼자', '함께', '무관'],
              selected: (v) => participation == v,
              onSelect: (v) => setState(() => participation = v),
            ),
          ),
          ActivityFormSection(
            number: 6,
            title: '한 번에 할 수 있는 시간',
            child: ActivityChoices<int>(
              values: const [30, 60, 120, 180, 240, 480],
              selected: (v) => minutes == v,
              describe: (v) => v == 480
                  ? '무관'
                  : v == 30
                  ? '30분'
                  : '${v ~/ 60}시간',
              onSelect: (v) => setState(() => minutes = v),
            ),
          ),
          ActivityFormSection(
            number: 7,
            title: '활동 난이도',
            child: ActivityChoices<int>(
              values: const [1, 2, 3],
              selected: (v) => level == v,
              describe: (v) => ['쉬움', '보통', '무관'][v - 1],
              onSelect: (v) => setState(() => level = v),
            ),
          ),
          ActivityCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('새로운 활동도 만나기', style: petText(18)),
              subtitle: Text(
                '끄면 익숙한 동네 활동을 추천해요. 이동 범위는 자동으로 넓히지 않아요.',
                style: petText(15, color: PetColors.secondary),
              ),
              value: expand,
              onChanged: (v) => setState(() => expand = v),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
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
  State<ActivityExperiencePage> createState() => _ExperienceState();
}

class _ExperienceState extends State<ActivityExperiencePage> {
  late final title = TextEditingController(
    text: widget.existing?['title'] ?? '',
  );
  late final description = TextEditingController(
    text: widget.existing?['description'] ?? '',
  );
  late final location = TextEditingController(
    text: widget.existing?['preferred_place'] ?? '',
  );
  late String? category =
      widget.existing?['category'] ?? widget.initialCategory;
  late String type = widget.existing?['activity_type'] ?? '';
  late bool active = widget.existing?['active'] ?? true;
  final days = <String>{}, times = <String>{};
  late final previousTime = widget.existing?['available_time'] as String? ?? '';
  bool busy = false,
      attempted = false,
      changedTime = false,
      titleTouched = false,
      descriptionTouched = false,
      categoryTouched = false;
  String get availability =>
      changedTime ? [...days, ...times].join(' ') : previousTime;
  bool get valid =>
      title.text.trim().isNotEmpty &&
      category != null &&
      description.text.trim().length >= 10;
  @override
  void dispose() {
    title.dispose();
    description.dispose();
    location.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    setState(() => attempted = true);
    if (!valid) return;
    setState(() => busy = true);
    try {
      await (widget.repository ?? ActivityRepository()).experience({
        'title': title.text.trim(),
        'category': category,
        'description': description.text.trim(),
        'available_time': availability,
        'preferred_place': location.text.trim(),
        'activity_type': type.isEmpty ? '무관' : type,
        'active': active,
      }, id: widget.existing?['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        await activityFailure(context, title: '경험을 저장하지 못했어요', onRetry: save);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget input(
    TextEditingController c,
    String label,
    String hint, {
    int lines = 1,
    int? limit,
  }) => TextField(
    controller: c,
    maxLines: lines,
    maxLength: limit,
    onChanged: (_) => setState(() {
      if (c == title) titleTouched = true;
      if (c == description) descriptionTouched = true;
    }),
    decoration: InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF4F8FB),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: ActivityScreen(
      title: widget.existing == null ? '나눌 경험 등록' : '나눌 경험 수정',
      tint: ActivityColors.pink,
      wallet: false,
      bottom: ActivityButton(
        busy
            ? '저장 중…'
            : valid
            ? '저장하기'
            : '필수 항목을 채워 주세요',
        onTap: busy || !valid ? null : save,
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const ActivityPrivacyNotice(),
          const SizedBox(height: 14),
          ActivityFormSection(
            number: 1,
            title: '경험 제목',
            required: true,
            pink: true,
            error: (attempted || titleTouched) && title.text.trim().isEmpty
                ? '경험 제목을 적어 주세요'
                : null,
            child: input(title, '나눌 경험', '예) 스마트폰 사용법 알려드리기', limit: 30),
          ),
          ActivityFormSection(
            number: 2,
            title: '분야',
            required: true,
            pink: true,
            error: (attempted || categoryTouched) && category == null
                ? '분야를 하나 골라 주세요'
                : null,
            child: ActivityChoices<String>(
              values: activityCategories,
              selected: (v) => category == v,
              onSelect: (v) => setState(() {
                category = v;
                categoryTouched = true;
              }),
            ),
          ),
          ActivityFormSection(
            number: 3,
            title: '경험 설명',
            required: true,
            pink: true,
            error:
                (attempted || descriptionTouched) &&
                    description.text.trim().length < 10
                ? '경험을 10자 이상 적어 주세요'
                : null,
            child: input(
              description,
              '경험 설명',
              '어떤 경험인지, 어떻게 도울 수 있는지 적어 주세요',
              lines: 4,
              limit: 300,
            ),
          ),
          ActivityFormSection(
            number: 4,
            title: '가능한 시간',
            pink: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (previousTime.isNotEmpty && !changedTime)
                  Text(
                    previousTime,
                    style: petText(16, color: PetColors.secondary),
                  ),
                ActivityChoices<String>(
                  values: const ['월', '화', '수', '목', '금', '토', '일'],
                  selected: days.contains,
                  onSelect: (v) => setState(() {
                    changedTime = true;
                    days.contains(v) ? days.remove(v) : days.add(v);
                  }),
                ),
                const SizedBox(height: 10),
                ActivityChoices<String>(
                  values: const ['오전', '오후', '저녁'],
                  selected: times.contains,
                  onSelect: (v) => setState(() {
                    changedTime = true;
                    times.contains(v) ? times.remove(v) : times.add(v);
                  }),
                ),
              ],
            ),
          ),
          ActivityFormSection(
            number: 5,
            title: '선호 장소',
            pink: true,
            child: input(location, '선호 장소', '예) 우리 동네 근처, 복지관'),
          ),
          ActivityFormSection(
            number: 6,
            title: '활동 형태',
            pink: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (type.isNotEmpty && !['대면', '비대면', '무관'].contains(type))
                  Text(
                    '기존 설정: $type',
                    style: petText(15, color: PetColors.secondary),
                  ),
                ActivityChoices<String>(
                  values: const ['대면', '비대면', '무관'],
                  selected: (v) => type == v,
                  onSelect: (v) => setState(() => type = v),
                ),
              ],
            ),
          ),
          ActivityCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('경험 나눔 참여 가능', style: petText(18)),
              subtitle: Text(
                '끄면 기관 모집에 지원할 수 없어요',
                style: petText(15, color: PetColors.secondary),
              ),
              value: active,
              onChanged: (v) => setState(() => active = v),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class ActivityPrivacyNotice extends StatelessWidget {
  const ActivityPrivacyNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFE2F1FC),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(
      '♧ 내 경험은 나만 볼 수 있어요. 모집에 지원하면 그때 내용만 해당 기관에 전달돼요.',
      style: petText(15, color: ActivityColors.blue),
    ),
  );
}

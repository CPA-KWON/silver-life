import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../ui/neighborhood_design.dart';
import '../social/social_form_widgets.dart';
import '../social/social_media.dart';
import '../social/photo_widgets.dart';

class FacilityGuidePage extends StatefulWidget {
  const FacilityGuidePage({super.key, required this.organizations});
  final List<Map<String, dynamic>> organizations;
  @override
  State<FacilityGuidePage> createState() => _GuideState();
}

class _GuideState extends State<FacilityGuidePage> {
  final form = GlobalKey<FormState>(),
      hours = TextEditingController(),
      floor = TextEditingController(),
      access = TextEditingController(),
      phone = TextEditingController(),
      steps = TextEditingController();
  late Map<String, dynamic>? org = widget.organizations.firstOrNull;
  bool? elevator, seating;
  bool busy = false;
  final images = <({XFile? file, String? path})>[];
  late Future<void> data = load();
  Future<void> load() async {
    final fid = org?['facility_id'];
    if (fid == null) return;
    final raw = await Supabase.instance.client.rpc(
      'facility_guide',
      params: {'target_facility': fid},
    );
    final g = Map<String, dynamic>.from(raw as Map);
    if (!mounted) return;
    hours.text = g['opening_hours'] ?? '';
    floor.text = g['floor_guide'] ?? '';
    access.text = g['accessibility'] ?? '';
    phone.text = g['contact_phone'] ?? '';
    steps.text = '${g['entry_steps'] ?? ''}';
    elevator = g['elevator'];
    seating = g['resting_seats'];
    images
      ..clear()
      ..addAll([
        for (final p in List<String>.from(g['image_paths'] ?? []))
          (file: null, path: p),
      ]);
  }

  @override
  void dispose() {
    hours.dispose();
    floor.dispose();
    access.dispose();
    phone.dispose();
    steps.dispose();
    super.dispose();
  }

  Future<void> photo() async {
    if (busy || images.length >= 5) return;
    final source = await choosePhotoSource(
      context,
      remaining: 5 - images.length,
    );
    if (source == null || !mounted) return;
    try {
      final files = await SocialMedia.chooseMany(
        limit: 5 - images.length,
        camera: source == PhotoSource.camera,
      );
      if (mounted) {
        setState(
          () => images.addAll([
            for (final f in files.take(5 - images.length))
              (file: f, path: null),
          ]),
        );
      }
    } catch (e) {
      if (mounted) await photoError(context, e);
    }
  }

  Future<void> save() async {
    if (busy || org?['facility_id'] == null || !form.currentState!.validate()) {
      return;
    }
    if (!await activityDialog(
      context,
      title: '시설 안내를 저장할까요?',
      message: '운영시간·층별 안내는 이용자에게 기관이 등록한 정보로 표시돼요. 현장과 맞는지 확인해 주세요.',
      action: '저장하기',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      for (var i = 0; i < images.length; i++) {
        final p = images[i];
        if (p.path == null) {
          images[i] = (
            file: p.file,
            path: await SocialMedia.upload(
              p.file!,
              folder: 'notices',
              owner: org!['id'],
            ),
          );
        }
      }
      await Supabase.instance.client.rpc(
        'facility_guide_save',
        params: {
          'target_org': org!['id'],
          'details': {
            'opening_hours': hours.text.trim(),
            'floor_guide': floor.text.trim(),
            'accessibility': access.text.trim(),
            'contact_phone': phone.text.trim(),
            'entry_steps': int.tryParse(steps.text.trim()),
            'elevator': elevator,
            'resting_seats': seating,
            'image_paths': [for (final p in images) p.path],
          },
        },
      );
      if (mounted) {
        await activityDialog(
          context,
          title: '시설 안내를 저장했어요',
          message: '시설 상세에서 확인할 수 있어요.',
          secondary: '',
          icon: Icons.check_circle_outline,
        );
      }
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '시설 안내를 저장하지 못했어요',
          message: '입력한 내용은 그대로 있어요. 기관 권한과 연결 상태를 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget input(
    TextEditingController controller,
    String label, {
    int maxLength = 2000,
    int lines = 3,
  }) => TextFormField(
    controller: controller,
    enabled: !busy,
    maxLength: maxLength,
    minLines: lines,
    maxLines: lines + 3,
    decoration: InputDecoration(labelText: label),
  );
  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: NeighborhoodScreen(
      title: '시설 안내 관리',
      tint: const Color(0xFFDCE5EE),
      bottom: org?['facility_id'] == null
          ? null
          : ActivityButton(busy ? '저장 중…' : '저장하기', onTap: busy ? null : save),
      child: FutureBuilder<void>(
        future: data,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const NeighborhoodLoading();
          }
          if (org?['facility_id'] == null) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: ActivityEmpty(
                '연결된 시설이 없어요',
                message: '기관 인증 정보에 시설이 연결된 뒤 이용할 수 있어요. 운영자에게 기관 연결을 요청해 주세요.',
                icon: Icons.business_outlined,
              ),
            );
          }
          if (s.hasError) {
            return ActivityEmpty(
              '시설 안내를 불러오지 못했어요',
              action: '다시 시도',
              onAction: () => setState(() {
                data = load();
              }),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.organizations.length > 1)
                    DropdownButtonFormField<String>(
                      initialValue: org!['id'],
                      items: [
                        for (final o in widget.organizations)
                          DropdownMenuItem(
                            value: o['id'],
                            child: Text('${o['name']}'),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (id) => setState(() {
                              org = widget.organizations.firstWhere(
                                (o) => o['id'] == id,
                              );
                              data = load();
                            }),
                    ),
                  NeighborhoodHero(
                    title: '${org!['name']}',
                    subtitle: '현장에서 확인한 안내만 적어 주세요. 모르는 항목은 비워 둘 수 있어요.',
                    color: PetColors.purple,
                  ),
                  const SizedBox(height: 18),
                  SocialFormCard('운영시간', child: input(hours, '운영시간·휴관일')),
                  SocialFormCard('층별 안내', child: input(floor, '입구에서 프로그램실까지')),
                  SocialFormCard(
                    '기관 연락처',
                    child: TextFormField(
                      controller: phone,
                      enabled: !busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: '기관 전화번호'),
                      validator: (v) =>
                          v == null ||
                              v.trim().isEmpty ||
                              RegExp(r'^[+0-9() -]{7,30}$').hasMatch(v.trim())
                          ? null
                          : '전화번호를 확인해 주세요',
                    ),
                  ),
                  SocialFormCard(
                    '이동 편의',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: elevator == null
                              ? 'unknown'
                              : elevator == true
                              ? 'yes'
                              : 'no',
                          decoration: const InputDecoration(labelText: '엘리베이터'),
                          items: const [
                            DropdownMenuItem(
                              value: 'unknown',
                              child: Text('확인 전'),
                            ),
                            DropdownMenuItem(value: 'yes', child: Text('있음')),
                            DropdownMenuItem(value: 'no', child: Text('없음')),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setState(
                                  () => elevator = v == 'unknown'
                                      ? null
                                      : v == 'yes',
                                ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: steps,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '입구 계단 수 · 모르면 비워 두세요',
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            final n = int.tryParse(v);
                            return n == null || n < 0 || n > 200
                                ? '0~200개로 적어 주세요'
                                : null;
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: seating == null
                              ? 'unknown'
                              : seating == true
                              ? 'yes'
                              : 'no',
                          decoration: const InputDecoration(labelText: '쉬는 의자'),
                          items: const [
                            DropdownMenuItem(
                              value: 'unknown',
                              child: Text('확인 전'),
                            ),
                            DropdownMenuItem(value: 'yes', child: Text('있음')),
                            DropdownMenuItem(value: 'no', child: Text('없음')),
                          ],
                          onChanged: busy
                              ? null
                              : (v) => setState(
                                  () => seating = v == 'unknown'
                                      ? null
                                      : v == 'yes',
                                ),
                        ),
                        const SizedBox(height: 12),
                        input(access, '기타 이동 안내'),
                      ],
                    ),
                  ),
                  SocialFormCard(
                    '안내도·입구 사진 · 최대 5장',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (i, p) in images.indexed)
                              SizedBox(
                                width: 90,
                                child: PhotoTile(
                                  file: p.file,
                                  path: p.path,
                                  index: i,
                                  onRemove: busy
                                      ? null
                                      : () =>
                                            setState(() => images.removeAt(i)),
                                ),
                              ),
                          ],
                        ),
                        OutlinedButton.icon(
                          onPressed: busy || images.length >= 5 ? null : photo,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('안내 이미지 추가'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

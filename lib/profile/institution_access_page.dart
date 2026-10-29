import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../activity/activity_forms.dart' show pickActivityPlace;
import '../activity/activity_agency_page.dart';
import '../activity/activity_repository.dart';
import '../community/new_post_page.dart' show newPostId;
import '../facility/naver_local_search.dart';
import '../facility/facility_repository.dart';
import '../social/social_form_widgets.dart';
import '../social/social_media.dart';
import '../social/photo_widgets.dart';
import '../ui/neighborhood_design.dart';

const _slate = Color(0xFF344C66);

class InstitutionAccessPage extends StatefulWidget {
  const InstitutionAccessPage({super.key});
  @override
  State<InstitutionAccessPage> createState() => _AccessState();
}

class _AccessState extends State<InstitutionAccessPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      department = TextEditingController(),
      phone = TextEditingController();
  final proofs = <XFile>[], uploaded = <String>[];
  late String requestId = newPostId();
  FacilityResult? facility;
  String kind = '복지관';
  final duties = <String>{};
  bool editing = false, busy = false, consent = false;
  late Future<Map<String, dynamic>?> state = load();
  Future<Map<String, dynamic>?> load() async {
    final c = Supabase.instance.client;
    return c
        .from('institution_access_requests')
        .select()
        .eq('user_id', c.auth.currentUser!.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<void> reload() async {
    final f = load();
    setState(() {
      state = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  @override
  void dispose() {
    name.dispose();
    department.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> chooseFacility() async {
    final p = await pickActivityPlace(context);
    if (p != null && mounted) setState(() => facility = p);
  }

  Future<void> photo() async {
    if (proofs.length + uploaded.length >= 3 || busy) return;
    final source = await choosePhotoSource(
      context,
      remaining: 3 - proofs.length - uploaded.length,
    );
    if (source == null || !mounted) return;
    try {
      final selected = await SocialMedia.chooseMany(
        limit: 3 - proofs.length - uploaded.length,
        camera: source == PhotoSource.camera,
      );
      if (mounted) {
        setState(
          () =>
              proofs.addAll(selected.take(3 - proofs.length - uploaded.length)),
        );
      }
    } catch (e) {
      if (mounted) await photoError(context, e);
    }
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    if (facility == null || duties.isEmpty || !consent) {
      await activityFailure(
        context,
        title: '입력한 내용을 확인해 주세요',
        message: '기관, 담당 업무, 정보 확인 동의를 모두 선택해 주세요.',
      );
      return;
    }
    if (!await activityDialog(
      context,
      title: '인증 요청을 보낼까요?',
      message: '보내주신 기관 정보와 연락처를 확인한 후 승인 여부를 알려드려요.',
      action: '인증 요청 보내기',
      secondary: '더 확인하기',
      color: _slate,
      rows: [
        ('기관', facility!.name),
        ('담당자', name.text.trim()),
        ('연락처', phone.text.trim()),
      ],
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      for (final p in proofs.toList()) {
        uploaded.add(await SocialMedia.upload(p, folder: 'org-proofs'));
        proofs.remove(p);
      }
      final c = Supabase.instance.client;
      final fid = await ensureFacility(facility!);
      await c.rpc(
        'institution_request_access',
        params: {
          'request_id': requestId,
          'details': {
            'facility_id': fid,
            'institution_kind': kind,
            'contact_name': name.text.trim(),
            'department': department.text.trim(),
            'duties': duties.toList(),
            'contact_phone': phone.text.trim(),
            'proof_paths': uploaded,
            'consent': consent,
          },
        },
      );
      if (!mounted) return;
      setState(() => editing = false);
      await reload();
      if (mounted) {
        await activityDialog(
          context,
          title: '인증 요청을 접수했어요',
          message: '기관 정보와 담당자 정보를 확인한 뒤 결과를 이 화면에서 알려드려요.',
          secondary: '',
          color: _slate,
          icon: Icons.check_circle_outline,
        );
      }
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '인증 요청을 보내지 못했어요',
          message: '입력한 내용은 그대로 있어요. 연결을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(Map<String, dynamic> r) async {
    if (!await activityDialog(
      context,
      title: '인증 요청을 취소할까요?',
      message: '심사 중인 요청을 취소해요. 나중에 다시 요청할 수 있어요.',
      action: '요청 취소하기',
      secondary: '심사 기다리기',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await Supabase.instance.client.rpc(
        'institution_cancel_access',
        params: {'request_id': r['id']},
      );
      requestId = newPostId();
      await reload();
    } catch (_) {
      if (mounted) await activityFailure(context, title: '요청을 취소하지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enterAgency() async {
    try {
      final home = await ActivityRepository().home();
      if (!mounted) return;
      final orgs = activityRows(home['organizations']);
      if (orgs.isEmpty) {
        await activityFailure(
          context,
          title: '기관 권한을 다시 확인해 주세요',
          message: '담당자 연결이 변경됐을 수 있어요. 기관에 문의해 주세요.',
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ActivityAgencyPage(organizations: orgs),
        ),
      );
    } catch (_) {
      if (mounted) await activityFailure(context, title: '기관 정보를 불러오지 못했어요');
    }
  }

  void editAgain(Map<String, dynamic> r) {
    name.text = r['contact_name'] ?? '';
    department.text = r['department'] ?? '';
    phone.text = r['contact_phone'] ?? '';
    kind = r['institution_kind'] ?? '복지관';
    duties
      ..clear()
      ..addAll(List<String>.from(r['duties'] ?? []));
    uploaded
      ..clear()
      ..addAll(List<String>.from(r['proof_paths'] ?? []));
    proofs.clear();
    consent = false;
    requestId = newPostId();
    // Select the facility again; never trust stale coordinates reconstructed from a name.
    setState(() => editing = true);
  }

  Widget intro() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const NeighborhoodHero(
        title: '복지관·주민센터 담당자이신가요?',
        subtitle: '인증을 받으면 프로그램 등록, 신청자 승인, 공식 공지를 올릴 수 있어요.',
        color: _slate,
      ),
      const NeighborhoodHeading('이렇게 진행돼요', color: _slate),
      ActivityCard(
        child: Column(
          children: [
            for (final (i, title, body) in [
              (1, '기관·담당자 정보 입력', '기관명, 담당 업무, 연락처'),
              (2, '재직 확인 자료 첨부', '명함 또는 재직증명서 사진 · 선택'),
              (3, '실버라이프 심사', '기관 대표번호와 담당자 정보를 확인해요.'),
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFF0F3F7),
                  child: Text('$i', style: petText(16, color: _slate)),
                ),
                title: Text(title, style: petText(18)),
                subtitle: Text(
                  body,
                  style: petText(15, color: PetColors.secondary),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 32),
      ActivityButton(
        '인증 요청 시작하기',
        color: _slate,
        onTap: () => setState(() => editing = true),
      ),
    ],
  );
  Widget requestForm() => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const NeighborhoodHeading('어느 기관인가요?', color: _slate),
        SocialFormCard(
          '기관명',
          required: true,
          child: OutlinedButton.icon(
            onPressed: busy ? null : chooseFacility,
            icon: const Icon(Icons.business_outlined),
            label: Text(facility?.name ?? '기관 찾기'),
          ),
        ),
        if (facility != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Text(
              facility!.address,
              style: petText(15, color: PetColors.secondary),
            ),
          ),
        SocialFormCard(
          '기관 종류',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in ['복지관', '주민센터', '경로당', '보건소', '기타'])
                ChoiceChip(
                  label: Text(t),
                  selected: kind == t,
                  onSelected: busy ? null : (_) => setState(() => kind = t),
                ),
            ],
          ),
        ),
        const NeighborhoodHeading('담당자 정보', color: _slate),
        SocialFormCard(
          '이름',
          required: true,
          child: TextFormField(
            controller: name,
            enabled: !busy,
            maxLength: 50,
            decoration: const InputDecoration(labelText: '담당자 이름'),
            validator: (v) => (v?.trim().isEmpty ?? true) ? '이름을 적어 주세요' : null,
          ),
        ),
        SocialFormCard(
          '부서·직책',
          child: TextFormField(
            controller: department,
            enabled: !busy,
            maxLength: 100,
            decoration: const InputDecoration(labelText: '부서·직책'),
          ),
        ),
        SocialFormCard(
          '담당 업무',
          required: true,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in ['프로그램 운영', '신청자 관리', '공지 작성', '경험 나눔 모집'])
                FilterChip(
                  label: Text(d),
                  selected: duties.contains(d),
                  onSelected: busy
                      ? null
                      : (v) => setState(
                          () => v ? duties.add(d) : duties.remove(d),
                        ),
                ),
            ],
          ),
        ),
        SocialFormCard(
          '연락처',
          required: true,
          child: Column(
            children: [
              TextFormField(
                controller: phone,
                enabled: !busy,
                keyboardType: TextInputType.phone,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '연락처',
                  hintText: '기관 대표번호와 내선번호',
                ),
                validator: (v) =>
                    RegExp(r'[0-9]').allMatches(v ?? '').length < 8
                    ? '연락 가능한 번호를 적어 주세요'
                    : null,
              ),
              Text(
                '심사 때 이 번호로 담당자 정보를 확인해요.',
                style: petText(14, color: PetColors.secondary),
              ),
            ],
          ),
        ),
        SocialFormCard(
          '재직 확인 자료 · 선택 · 최대 3장',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, p) in uploaded.indexed)
                    SizedBox(
                      width: 90,
                      child: PhotoTile(
                        path: p,
                        index: i,
                        onRemove: busy
                            ? null
                            : () => setState(() => uploaded.remove(p)),
                      ),
                    ),
                  for (final (i, p) in proofs.indexed)
                    SizedBox(
                      width: 90,
                      child: PhotoTile(
                        file: p,
                        index: uploaded.length + i,
                        onRemove: busy
                            ? null
                            : () => setState(() => proofs.remove(p)),
                      ),
                    ),
                ],
              ),
              TextButton.icon(
                onPressed: busy || proofs.length + uploaded.length >= 3
                    ? null
                    : photo,
                icon: const Icon(Icons.add),
                label: const Text('자료 추가'),
              ),
              Text(
                '심사 담당자만 확인해요. 주민등록번호 등 불필요한 개인정보는 가려 주세요.',
                style: petText(14, color: PetColors.secondary),
              ),
            ],
          ),
        ),
        ActivityCard(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consent,
            onChanged: busy
                ? null
                : (v) => setState(() => consent = v ?? false),
            title: Text('기관 정보 확인·이용에 동의해요', style: petText(17)),
            subtitle: Text(
              '허위 요청은 이용이 제한될 수 있어요.',
              style: petText(14, color: PetColors.secondary),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ActivityButton(
          busy ? '보내는 중…' : '인증 요청 보내기',
          color: _slate,
          onTap: busy ? null : submit,
        ),
      ],
    ),
  );
  Widget status(Map<String, dynamic> r) {
    final approved = r['status'] == 'approved',
        rejected = r['status'] == 'rejected';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ActivityCard(
          color: approved
              ? neighborhoodMint
              : rejected
              ? const Color(0xFFFBE1E3)
              : neighborhoodAmber,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              approved
                  ? Icons.verified_outlined
                  : rejected
                  ? Icons.error_outline
                  : Icons.schedule,
              size: 36,
              color: approved
                  ? PetColors.green
                  : rejected
                  ? Colors.redAccent
                  : _slate,
            ),
            title: Text(
              approved
                  ? '기관 담당자 인증 완료'
                  : rejected
                  ? '인증 반려'
                  : '심사 대기 중',
              style: petText(22),
            ),
            subtitle: Text(
              '${r['institution_name']}',
              style: petText(15, color: PetColors.secondary),
            ),
          ),
        ),
        const SizedBox(height: 18),
        ActivityCard(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.check_circle, color: PetColors.green),
                title: Text('요청 접수', style: petText(18)),
                subtitle: Text(
                  _date(r['created_at']),
                  style: petText(14, color: PetColors.secondary),
                ),
              ),
              ListTile(
                leading: Icon(
                  rejected ? Icons.error_outline : Icons.search,
                  color: rejected ? Colors.redAccent : PetColors.orange,
                ),
                title: Text(
                  rejected
                      ? '반려됐어요'
                      : approved
                      ? '확인했어요'
                      : '심사 중',
                  style: petText(18),
                ),
                subtitle: Text(
                  rejected
                      ? '${r['rejection_reason'] ?? '기관에 문의해 주세요.'}'
                      : approved
                      ? '기관과 담당자 정보를 확인했어요.'
                      : '기관 정보와 연락처를 확인한 뒤 결과를 알려드려요.',
                  style: petText(15, color: PetColors.secondary),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.verified_outlined,
                  color: approved ? PetColors.blue : PetColors.secondary,
                ),
                title: Text('승인', style: petText(18)),
                subtitle: Text(
                  approved
                      ? '이제 기관 관리 기능을 이용할 수 있어요.'
                      : '승인 여부는 이 화면에서 확인할 수 있어요.',
                  style: petText(15, color: PetColors.secondary),
                ),
              ),
            ],
          ),
        ),
        const NeighborhoodHeading('보낸 내용', color: _slate),
        ActivityCard(
          child: Column(
            children: [
              for (final (k, v) in [
                ('기관', '${r['institution_name']}'),
                ('담당자', '${r['contact_name']} · ${r['department']}'),
                ('담당 업무', List<String>.from(r['duties'] ?? []).join(', ')),
                ('연락처', '${r['contact_phone']}'),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(k, style: petText(15, color: PetColors.secondary)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          v,
                          textAlign: TextAlign.end,
                          style: petText(17),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        ActivityButton(
          approved
              ? '기관 관리 시작하기'
              : rejected
              ? '정보 고쳐서 다시 요청'
              : '심사 상태 새로고침',
          color: _slate,
          onTap: busy
              ? null
              : approved
              ? enterAgency
              : rejected
              ? () => editAgain(r)
              : reload,
        ),
        if (!approved && !rejected)
          TextButton(
            onPressed: busy ? null : () => cancel(r),
            child: const Text('요청 취소하기'),
          ),
      ],
    );
  }

  String _date(dynamic s) {
    final d = DateTime.tryParse('$s')?.toLocal();
    return d == null
        ? ''
        : '${d.month}월 ${d.day}일 ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: NeighborhoodScreen(
      title: '기관 담당자 인증',
      tint: const Color(0xFFDCE5EE),
      child: FutureBuilder<Map<String, dynamic>?>(
        future: state,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const NeighborhoodLoading();
          }
          if (s.hasError) {
            return ActivityEmpty(
              '인증 정보를 불러오지 못했어요',
              message: '다시 시도해 주세요. 계속되지 않으면 운영자에게 문의해 주세요.',
              action: '다시 시도',
              onAction: reload,
            );
          }
          final r = s.data;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: editing
                ? requestForm()
                : r == null || r['status'] == 'cancelled'
                ? intro()
                : status(r),
          );
        },
      ),
    ),
  );
}

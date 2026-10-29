import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/region_picker.dart';
import '../core/korea_regions.dart';
import '../core/phone_call.dart';
import '../community/new_post_page.dart' show newPostId;
import '../social/social_form_widgets.dart';
import '../social/social_media.dart';
import '../social/photo_widgets.dart';
import '../ui/neighborhood_design.dart';
import '../activity/activity_detail_page.dart';
import '../activity/activity_map_page.dart';
import 'notice_repository.dart';

const _noticeKinds = ['전체', '복지관', '주민센터', '보건소', '경로당', '기타'];
const _slate = Color(0xFF344C66);
String noticeDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? ''
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

String noticeStatus(NoticeData n) {
  if (n['published'] != true) return '비공개';
  final end = DateTime.tryParse('${n['expires_at']}'),
      start = DateTime.tryParse('${n['publish_at']}');
  if (end != null && end.isBefore(DateTime.now())) return '게시 종료';
  if (start != null && start.isAfter(DateTime.now())) return '예약';
  return '게시 중';
}

String _kind(NoticeData n) => '${n['institution_kind'] ?? '기타'}';
Widget _org(NoticeData n) => Row(
  children: [
    NeighborAvatar(
      _kind(n) == '기타' ? '${n['org_name'] ?? '기관'}' : _kind(n),
      radius: 23,
      color: switch (_kind(n)) {
        '보건소' => PetColors.green,
        '복지관' => PetColors.purple,
        _ => PetColors.blue,
      },
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${n['org_name'] ?? '기관 공지'}', style: petText(18)),
          Text(
            '${n['region_sigungu'] ?? ''} ${noticeDate(n['published_at'] ?? n['created_at'])}',
            style: petText(13, color: PetColors.secondary),
          ),
        ],
      ),
    ),
    const PetPill(
      '공식',
      color: neighborhoodAmber,
      ink: PetColors.orange,
      fontSize: 12,
    ),
  ],
);
Widget _card(
  NoticeData n, {
  required VoidCallback onTap,
  List<Widget> actions = const [],
}) => Padding(
  padding: const EdgeInsets.only(bottom: 14),
  child: ActivityCard(
    border: BorderSide(
      color: n['important'] == true
          ? PetColors.orange
          : const Color(0xFFF7DCA7),
      width: n['important'] == true ? 2 : 1,
    ),
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _org(n),
        const SizedBox(height: 14),
        Text('${n['title']}', style: petText(21)),
        if ('${n['summary'] ?? n['body'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${n['summary'] ?? n['body']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: petText(16, color: PetColors.secondary),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            if (n['important'] == true)
              const PetPill(
                '중요',
                color: Color(0xFFFFE9E7),
                ink: Colors.redAccent,
                fontSize: 13,
              ),
            if (n['pinned'] == true) const PetPill('상단 고정', fontSize: 13),
            if (n['reader_count'] != null)
              PetPill('읽은 이웃 ${n['reader_count']}명', fontSize: 12),
            ...actions,
          ],
        ),
      ],
    ),
  ),
);

class NoticeDetailPage extends StatefulWidget {
  const NoticeDetailPage({super.key, required this.id, this.repository});
  final String id;
  final NoticeRepository? repository;
  @override
  State<NoticeDetailPage> createState() => _DetailState();
}

class _DetailState extends State<NoticeDetailPage> {
  late final repo = widget.repository ?? NoticeRepository();
  late Future<NoticeData> data = repo.detail(widget.id);
  @override
  Widget build(BuildContext c) => FutureBuilder<NoticeData>(
    future: data,
    builder: (c, s) {
      final n = s.data, phone = '${n?['telephone'] ?? ''}'.trim();
      return NeighborhoodScreen(
        title: '동네 소식',
        tint: neighborhoodAmber,
        bottom: phone.isEmpty
            ? null
            : ActivityButton(
                '기관에 전화',
                icon: Icons.phone_outlined,
                color: PetColors.green,
                onTap: () => callFacility(c, phone),
              ),
        child: s.connectionState != ConnectionState.done
            ? const NeighborhoodLoading()
            : s.hasError
            ? ActivityEmpty(
                '게시가 종료됐거나 공지를 불러오지 못했어요.',
                action: '다시 시도',
                onAction: () => setState(() {
                  data = repo.detail(widget.id);
                }),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ActivityCard(child: _org(n!)),
                  const SizedBox(height: 16),
                  ActivityCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            if (n['important'] == true)
                              const PetPill(
                                '중요',
                                color: Color(0xFFFFE9E7),
                                ink: Colors.redAccent,
                              ),
                            if (n['expires_at'] != null)
                              PetPill(
                                '${noticeDate(n['expires_at'])}까지',
                                fontSize: 13,
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${n['title']}',
                          style: petText(25, weight: FontWeight.w800),
                        ),
                        const SizedBox(height: 20),
                        SelectableText(
                          '${n['body']}',
                          style: petText(19, weight: FontWeight.w500),
                        ),
                        for (final (i, path) in List<String>.from(
                          n['image_paths'] ?? [],
                        ).indexed)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                c,
                                MaterialPageRoute(
                                  builder: (_) => PhotoViewer(
                                    photos: [
                                      for (final p in List<String>.from(
                                        n['image_paths'],
                                      ))
                                        (file: null, path: p),
                                    ],
                                    initialIndex: i,
                                  ),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AspectRatio(
                                  aspectRatio: 4 / 3,
                                  child: SocialPhoto(path: path),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 18),
                        Text(
                          '게시 ${noticeDate(n['published_at'] ?? n['created_at'])}${n['reader_count'] == null ? '' : ' · 읽은 이웃 ${n['reader_count']}명'}',
                          style: petText(14, color: PetColors.secondary),
                        ),
                        if ('${n['source_url'] ?? ''}'.isNotEmpty)
                          TextButton.icon(
                            onPressed: () =>
                                openSource(c, '${n['source_url']}'),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('기관 원문 보기'),
                          ),
                      ],
                    ),
                  ),
                  if ((n['programs'] as List? ?? []).isNotEmpty) ...[
                    const NeighborhoodHeading(
                      '함께 보면 좋아요',
                      color: PetColors.orange,
                    ),
                    for (final raw in n['programs'])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ActivityCard(
                          onTap: () => Navigator.push(
                            c,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ActivityDetailPage(programId: raw['id']),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.event_available_outlined,
                              color: PetColors.blue,
                            ),
                            title: Text('${raw['title']}', style: petText(19)),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      ),
                  ],
                  if (n['facility'] is Map) ...[
                    const NeighborhoodHeading('시설 위치', color: PetColors.orange),
                    ActivityCard(
                      onTap: () => openNoticeMap(
                        c,
                        Map<String, dynamic>.from(n['facility']),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.map_outlined,
                          color: PetColors.green,
                        ),
                        title: Text(
                          '${n['facility']['name']}',
                          style: petText(19),
                        ),
                        subtitle: Text(
                          '${n['facility']['address'] ?? ''}',
                          style: petText(15, color: PetColors.secondary),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    ),
                  ],
                ],
              ),
      );
    },
  );
}

Future<void> openNoticeMap(BuildContext c, NoticeData f) async {
  await Navigator.push(
    c,
    PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, a, b) => ActivityMapPage(
        program: {...f, 'title': f['name'], 'place_name': f['name']},
      ),
    ),
  );
}

Future<void> openSource(BuildContext c, String url) async {
  final link = Uri.tryParse(url);
  if (link == null ||
      link.scheme != 'https' ||
      link.host.isEmpty ||
      link.userInfo.isNotEmpty) {
    return;
  }
  try {
    if (!await launchUrl(link, mode: LaunchMode.externalApplication)) {
      throw StateError('open');
    }
  } catch (_) {
    if (c.mounted) await activityFailure(c, title: '원문을 열지 못했어요', message: url);
  }
}

class NoticeListPage extends StatefulWidget {
  const NoticeListPage({super.key, this.repository});
  final NoticeRepository? repository;
  @override
  State<NoticeListPage> createState() => _ListState();
}

class _ListState extends State<NoticeListPage> {
  late final repo = widget.repository ?? NoticeRepository();
  late Future<List<NoticeData>> data = repo.feed();
  String kind = '전체';
  Future<void> reload() async {
    final f = repo.feed();
    setState(() {
      data = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '동네 소식',
    subtitle: '기관이 올린 공식 안내예요',
    tint: neighborhoodAmber,
    child: FutureBuilder<List<NoticeData>>(
      future: data,
      builder: (c, s) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 8,
              children: [
                for (final k in _noticeKinds)
                  ChoiceChip(
                    label: Text(k),
                    selected: k == kind,
                    onSelected: (_) => setState(() => kind = k),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ActivityCard(
              color: const Color(0xFFFFF3DA),
              child: Text(
                '공식 표시는 확인된 기관만 올릴 수 있어요. 이웃 글은 커뮤니티에 있어요.',
                style: petText(15, color: const Color(0xFF75501A)),
              ),
            ),
            const SizedBox(height: 16),
            if (s.connectionState != ConnectionState.done)
              const SizedBox(height: 300, child: NeighborhoodLoading())
            else if (s.hasError)
              ActivityEmpty(
                '기관 공지를 불러오지 못했어요.',
                action: '다시 시도',
                onAction: reload,
              )
            else if (!s.data!.any((n) => kind == '전체' || _kind(n) == kind))
              const ActivityEmpty(
                '아직 등록된 기관 공지가 없어요.',
                message: '새 공지가 올라오면 여기에서 확인할 수 있어요.',
              )
            else
              for (final n in s.data!.where(
                (n) => kind == '전체' || _kind(n) == kind,
              ))
                _card(
                  n,
                  onTap: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                      builder: (_) =>
                          NoticeDetailPage(id: n['id'], repository: repo),
                    ),
                  ),
                ),
          ],
        ),
      ),
    ),
  );
}

class NoticeManagePage extends StatefulWidget {
  const NoticeManagePage({
    super.key,
    required this.organizations,
    this.repository,
  });
  final List<NoticeData> organizations;
  final NoticeRepository? repository;
  @override
  State<NoticeManagePage> createState() => _ManageState();
}

class _ManageState extends State<NoticeManagePage> {
  late final repo = widget.repository ?? NoticeRepository();
  late Future<List<NoticeData>> data = repo.managed();
  String tab = '게시 중';
  bool busy = false;
  Future<void> reload() async {
    final f = repo.managed();
    setState(() {
      data = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> edit([NoticeData? n]) async {
    final result = await Navigator.push<NoticeData>(
      context,
      MaterialPageRoute(
        builder: (_) => NoticeForm(
          organizations: widget.organizations,
          notice: n,
          repository: repo,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(
        () => tab = result['published'] != true ? '숨김' : noticeStatus(result),
      );
    }
    await reload();
  }

  Future<void> publish(NoticeData n) async {
    if (busy) return;
    final value = n['published'] != true;
    if (!await activityDialog(
      context,
      title: value ? '이 공지를 게시할까요?' : '공지 게시를 중지할까요?',
      message: value
          ? (noticeStatus({...n, 'published': true}) == '예약'
                ? '예약한 시각부터 선택한 지역에 표시돼요.'
                : '선택한 지역의 홈에 기관명과 함께 표시돼요.')
          : '홈에서는 내려가고 기관 관리에는 기록이 남아요.',
      action: value ? '게시하기' : '게시 중지',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await repo.publish(n['id'], value);
      if (mounted) {
        setState(
          () => tab = value ? noticeStatus({...n, 'published': true}) : '숨김',
        );
      }
      await reload();
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '처리하지 못했어요',
          message: '기관 권한과 게시 종료일을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: '공지 관리',
    tint: const Color(0xFFDCE5EE),
    bottom: ActivityButton(
      '+ 새 공지 쓰기',
      onTap: busy || widget.organizations.isEmpty ? null : () => edit(),
    ),
    child: FutureBuilder<List<NoticeData>>(
      future: data,
      builder: (c, s) {
        final rows = s.data ?? [];
        bool visible(NoticeData n) => tab == '숨김'
            ? ['비공개', '게시 종료'].contains(noticeStatus(n))
            : noticeStatus(n) == tab;
        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.organizations.isNotEmpty)
                Text(
                  widget.organizations.map((o) => o['name']).join(' · '),
                  style: petText(16, color: PetColors.secondary),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in ['게시 중', '예약', '숨김'])
                    ChoiceChip(
                      label: Text(
                        '$t ${rows.where((n) => t == '숨김' ? ['비공개', '게시 종료'].contains(noticeStatus(n)) : noticeStatus(n) == t).length}',
                      ),
                      selected: tab == t,
                      onSelected: (_) => setState(() => tab = t),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (s.connectionState != ConnectionState.done)
                const SizedBox(height: 300, child: NeighborhoodLoading())
              else if (s.hasError)
                ActivityEmpty(
                  '공지 목록을 불러오지 못했어요',
                  action: '다시 시도',
                  onAction: reload,
                )
              else if (!rows.any(visible))
                ActivityEmpty(
                  tab == '숨김'
                      ? '숨긴 공지가 없어요'
                      : '${tab == '예약' ? '예약한' : '게시 중인'} 공지가 없어요',
                  action: '공지 작성',
                  onAction: () => edit(),
                )
              else
                for (final n in rows.where(visible))
                  _card(
                    n,
                    onTap: () => Navigator.push(
                      c,
                      MaterialPageRoute(
                        builder: (_) =>
                            NoticeDetailPage(id: n['id'], repository: repo),
                      ),
                    ),
                    actions: [
                      PetPill(noticeStatus(n), fontSize: 13),
                      TextButton(
                        onPressed: busy ? null : () => edit(n),
                        child: const Text('수정'),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => publish(n),
                        child: Text(n['published'] == true ? '게시 중지' : '게시하기'),
                      ),
                    ],
                  ),
            ],
          ),
        );
      },
    ),
  );
}

class NoticeForm extends StatefulWidget {
  const NoticeForm({
    super.key,
    required this.organizations,
    this.notice,
    this.repository,
  });
  final List<NoticeData> organizations;
  final NoticeData? notice;
  final NoticeRepository? repository;
  @override
  State<NoticeForm> createState() => _FormState();
}

class _FormState extends State<NoticeForm> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.notice?['title']),
      body = TextEditingController(text: widget.notice?['body']),
      url = TextEditingController(text: widget.notice?['source_url']),
      phone = TextEditingController(text: widget.notice?['contact_phone']);
  late final repo = widget.repository ?? NoticeRepository();
  late String? org =
      widget.notice?['org_id'] ?? widget.organizations.firstOrNull?['id'];
  late String sido = widget.notice?['region_sido'] ?? kKoreaRegions.keys.first,
      district = widget.notice?['region_sigungu'] ?? kKoreaRegions[sido]!.first,
      kind = widget.notice?['institution_kind'] ?? '기타';
  late bool important = widget.notice?['important'] == true,
      pinned = widget.notice?['pinned'] == true;
  late DateTime? end = DateTime.tryParse('${widget.notice?['expires_at']}')
          ?.toLocal(),
      start = DateTime.tryParse('${widget.notice?['publish_at']}')?.toLocal();
  late final images = <({XFile? file, String? path})>[
    for (final p in List<String>.from(widget.notice?['image_paths'] ?? []))
      (file: null, path: p),
  ];
  late final linked = List<String>.from(
    widget.notice?['linked_programs'] ??
        [
          if (widget.notice?['linked_program'] != null)
            widget.notice!['linked_program'],
        ],
  );
  late Future<List<NoticeData>> programs = org == null
      ? Future.value([])
      : repo.programs(org!);
  final requestId = newPostId();
  String? savedId;
  bool busy = false, touched = false;
  @override
  void initState() {
    super.initState();
    if (widget.notice == null) loadRegion();
  }

  Future<void> loadRegion() async {
    try {
      final r = await repo.region();
      if (mounted && !touched && kKoreaRegions.containsKey(r['region_sido'])) {
        setState(() {
          sido = r['region_sido'];
          district = kKoreaRegions[sido]!.contains(r['region_sigungu'])
              ? r['region_sigungu']
              : kKoreaRegions[sido]!.first;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    url.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> chooseDate(bool schedule) async {
    final date = await pickSocialDate(context, schedule ? start : end);
    if (date == null || !mounted) return;
    if (schedule) {
      final time = await pickSocialTime(
        context,
        start == null ? TimeOfDay.now() : TimeOfDay.fromDateTime(start!),
      );
      if (time == null || !mounted) return;
      final at = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!at.isAfter(DateTime.now())) {
        await activityFailure(context, title: '지금 이후의 예약 시간을 골라 주세요');
        return;
      }
      setState(() => start = at);
    } else {
      setState(() => end = DateTime(date.year, date.month, date.day, 23, 59));
    }
  }

  NoticeData payload() => {
    'client_request_id': requestId,
    'org_id': org,
    'title': title.text.trim(),
    'body': body.text.trim(),
    'source_url': url.text.trim(),
    'region_sido': sido,
    'region_sigungu': district,
    'expires_at': end?.toUtc().toIso8601String(),
    'publish_at': start?.toUtc().toIso8601String(),
    'institution_kind': kind,
    'contact_phone': phone.text.trim(),
    'important': important,
    'pinned': pinned,
    'image_paths': [
      for (final p in images)
        if (p.path != null) p.path,
    ],
    'linked_programs': linked,
  };
  Future<void> photo() async {
    if (busy || images.length >= 5) return;
    final source = await choosePhotoSource(
      context,
      remaining: 5 - images.length,
    );
    if (source == null || !mounted) return;
    try {
      final fs = await SocialMedia.chooseMany(
        limit: 5 - images.length,
        camera: source == PhotoSource.camera,
      );
      for (final f in fs) {
        if (await f.length() > 10 * 1024 * 1024) {
          throw StateError('사진은 한 장에 10MB까지 올릴 수 있어요.');
        }
      }
      if (mounted) {
        setState(
          () => images.addAll([
            for (final f in fs.take(5 - images.length)) (file: f, path: null),
          ]),
        );
      }
    } catch (e) {
      if (mounted) await photoError(context, e);
    }
  }

  Future<void> preview() async {
    if (!form.currentState!.validate() || org == null) return;
    final data = {
      ...payload(),
      'org_name': widget.organizations
          .where((o) => o['id'] == org)
          .firstOrNull?['name'],
    };
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NeighborhoodScreen(
          title: '공지 미리보기',
          tint: neighborhoodAmber,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const PetPill('미리보기 · 아직 저장하지 않은 내용이에요', fontSize: 13),
              const SizedBox(height: 16),
              ActivityCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _org(data),
                    const SizedBox(height: 18),
                    Text(title.text.trim(), style: petText(25)),
                    const SizedBox(height: 18),
                    Text(
                      body.text.trim(),
                      style: petText(19, weight: FontWeight.w500),
                    ),
                    for (final p in images)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: SocialPhoto(file: p.file, path: p.path),
                        ),
                      ),
                  ],
                ),
              ),
              if (start != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '예약: ${noticeDate(start)} ${start!.hour}:${start!.minute.toString().padLeft(2, '0')}',
                    style: petText(17),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> selectPrograms() async {
    List<NoticeData> rows;
    try {
      rows = await programs;
    } catch (_) {
      if (mounted) await activityFailure(context, title: '연결할 프로그램을 불러오지 못했어요');
      return;
    }
    if (!mounted) return;
    final selected = linked.toSet();
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('연결할 프로그램 · 최대 10개', style: petText(22)),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('등록한 프로그램이 없어요. 프로그램을 먼저 등록해 주세요.'),
                        ),
                      for (final p in rows)
                        CheckboxListTile(
                          title: Text('${p['title']}'),
                          value: selected.contains(p['id']),
                          onChanged: (v) => set(() {
                            if (v == true) {
                              if (selected.length < 10) selected.add(p['id']);
                            } else {
                              selected.remove(p['id']);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ActivityButton(
                    '선택 완료',
                    onTap: () => Navigator.pop(c, selected.toList()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        linked
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> changeOrg(String value) async {
    if (busy || savedId != null || widget.notice != null) return;
    if (images.isNotEmpty &&
        !await activityDialog(
          context,
          title: '기관을 바꿀까요?',
          message: '다른 기관에 올릴 사진과 연결 프로그램은 다시 골라 주세요.',
          action: '기관 바꾸기',
        )) {
      return;
    }
    if (mounted) {
      setState(() {
        org = value;
        images.clear();
        linked.clear();
        programs = repo.programs(value);
      });
    }
  }

  Future<void> save({bool publish = false}) async {
    if (busy || org == null || !form.currentState!.validate()) return;
    if (end != null &&
        (!end!.isAfter(DateTime.now()) ||
            (start != null && !end!.isAfter(start!)))) {
      await activityFailure(
        context,
        title: '게시 종료일을 다시 골라 주세요',
        message: '게시 시작일 이후로 선택해 주세요.',
      );
      return;
    }
    if (publish &&
        !await activityDialog(
          context,
          title: start == null ? '이 공지를 올릴까요?' : '예약한 시간에 게시할까요?',
          message: '선택한 지역에 기관명과 함께 공식 공지가 표시돼요.',
          action: start == null ? '공지 올리기' : '예약 게시',
          rows: [
            (
              '기관',
              '${widget.organizations.where((o) => o['id'] == org).firstOrNull?['name'] ?? ''}',
            ),
            ('제목', title.text.trim()),
          ],
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
              owner: org,
            ),
          );
        }
      }
      final id = await repo.save(
        payload(),
        id: savedId ?? widget.notice?['id'],
      );
      savedId = id;
      if (publish) await repo.publish(id, true);
      if (mounted) {
        await activityDialog(
          context,
          title: publish
              ? (start == null ? '공지를 올렸어요' : '예약 게시를 설정했어요')
              : '공지를 저장했어요',
          message: publish
              ? '기관 공지 관리에서 확인할 수 있어요.'
              : '비공개로 저장했어요. 관리 화면에서 내용을 확인하고 게시해 주세요.',
          secondary: '',
          icon: Icons.check_circle_outline,
        );
        if (mounted) {
          Navigator.pop(context, <String, dynamic>{
            ...payload(),
            'id': id,
            'published': publish || widget.notice?['published'] == true,
          });
        }
      }
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: savedId != null && publish
              ? '공지는 저장됐지만 게시하지 못했어요'
              : '저장하지 못했어요',
          message: '입력한 내용은 그대로 있어요. 연결과 기관 권한을 확인한 뒤 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: NeighborhoodScreen(
      title: widget.notice == null ? '공지 등록' : '공지 수정',
      tint: const Color(0xFFDCE5EE),
      bottom: org == null
          ? null
          : Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: busy ? null : preview,
                    child: const Text('미리보기'),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ActivityButton(
                    busy
                        ? '처리 중…'
                        : widget.notice?['published'] == true
                        ? '수정 저장하기'
                        : '공지 올리기',
                    onTap: busy
                        ? null
                        : () => save(
                            publish: widget.notice?['published'] != true,
                          ),
                  ),
                ),
              ],
            ),
      child: org == null
          ? const ActivityEmpty(
              '기관 담당자만 공지를 등록할 수 있어요',
              icon: Icons.lock_outline,
            )
          : AbsorbPointer(
              absorbing: busy,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.organizations.length > 1)
                        DropdownButtonFormField<String>(
                          initialValue: org,
                          items: [
                            for (final o in widget.organizations)
                              DropdownMenuItem(
                                value: o['id'],
                                child: Text('${o['name']}'),
                              ),
                          ],
                          onChanged:
                              busy || savedId != null || widget.notice != null
                              ? null
                              : (v) => changeOrg(v!),
                        ),
                      SocialFormCard(
                        '제목',
                        step: 1,
                        color: _slate,
                        required: true,
                        child: TextFormField(
                          controller: title,
                          enabled: !busy,
                          maxLength: 100,
                          decoration: const InputDecoration(labelText: '제목'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? '제목을 적어 주세요'
                              : null,
                        ),
                      ),
                      SocialFormCard(
                        '내용',
                        step: 2,
                        color: _slate,
                        required: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: body,
                              enabled: !busy,
                              minLines: 5,
                              maxLines: 12,
                              maxLength: 5000,
                              decoration: const InputDecoration(
                                labelText: '공지 내용',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? '공지 내용을 적어 주세요'
                                  : null,
                            ),
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
                                          : () => setState(
                                              () => images.removeAt(i),
                                            ),
                                    ),
                                  ),
                              ],
                            ),
                            OutlinedButton.icon(
                              onPressed: busy || images.length >= 5
                                  ? null
                                  : photo,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: Text('사진·안내문 붙이기 (${images.length}/5)'),
                            ),
                          ],
                        ),
                      ),
                      SocialFormCard(
                        '표시',
                        step: 3,
                        color: _slate,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              label: const Text('중요 공지'),
                              selected: important,
                              onSelected: busy
                                  ? null
                                  : (v) => setState(() => important = v),
                            ),
                            FilterChip(
                              label: const Text('상단 고정'),
                              selected: pinned,
                              onSelected: busy
                                  ? null
                                  : (v) => setState(() => pinned = v),
                            ),
                          ],
                        ),
                      ),
                      SocialFormCard(
                        '연결할 프로그램 · 선택',
                        step: 4,
                        color: _slate,
                        child: FutureBuilder<List<NoticeData>>(
                          future: programs,
                          builder: (c, p) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final id in linked)
                                    InputChip(
                                      label: Text(
                                        '${p.data?.where((r) => r['id'] == id).firstOrNull?['title'] ?? '연결한 프로그램'}',
                                      ),
                                      onDeleted: busy
                                          ? null
                                          : () => setState(
                                              () => linked.remove(id),
                                            ),
                                    ),
                                ],
                              ),
                              if (p.hasError)
                                TextButton(
                                  onPressed: () => setState(() {
                                    programs = repo.programs(org!);
                                  }),
                                  child: const Text('프로그램 다시 불러오기'),
                                ),
                              TextButton.icon(
                                onPressed: busy ? null : selectPrograms,
                                icon: const Icon(Icons.add),
                                label: const Text('더하기'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SocialFormCard(
                        '게시 지역',
                        required: true,
                        child: RegionPicker(
                          initialSido: sido,
                          initialSigungu: district,
                          onChanged: (a, b) => setState(() {
                            sido = a;
                            district = b;
                            touched = true;
                          }),
                        ),
                      ),
                      SocialFormCard(
                        '기관 종류·연락처',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final k in _noticeKinds.skip(1))
                                  ChoiceChip(
                                    label: Text(k),
                                    selected: kind == k,
                                    onSelected: busy
                                        ? null
                                        : (_) => setState(() => kind = k),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: phone,
                              enabled: !busy,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: '문의 전화 (선택)',
                              ),
                              validator: (v) =>
                                  v == null ||
                                      v.trim().isEmpty ||
                                      RegExp(r'^[+0-9() -]{7,30}$')
                                          .hasMatch(v.trim())
                                  ? null
                                  : '기관 전화번호를 확인해 주세요',
                            ),
                          ],
                        ),
                      ),
                      SocialFormCard(
                        '게시 시간·원문',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: url,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                labelText: '원문 링크 (선택)',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return null;
                                final uri = Uri.tryParse(v.trim());
                                return uri == null ||
                                        uri.scheme != 'https' ||
                                        uri.host.isEmpty ||
                                        uri.userInfo.isNotEmpty ||
                                        v.length > 2048
                                    ? 'https://로 시작하는 원문 주소를 입력해주세요.'
                                    : null;
                              },
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: busy ? null : () => chooseDate(true),
                              child: Text(
                                start == null
                                    ? '예약 게시 시간 선택'
                                    : '예약 ${noticeDate(start)} ${start!.hour}:${start!.minute.toString().padLeft(2, '0')}',
                              ),
                            ),
                            if (start != null)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() => start = null),
                                child: const Text('예약 해제'),
                              ),
                            TextButton(
                              onPressed: busy ? null : () => chooseDate(false),
                              child: Text(
                                end == null
                                    ? '게시 종료일 선택 (선택)'
                                    : '종료 ${noticeDate(end)}',
                              ),
                            ),
                            if (end != null)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() => end = null),
                                child: const Text('종료일 해제'),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => save(),
                        child: const Text('비공개 저장하기'),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
    ),
  );
}

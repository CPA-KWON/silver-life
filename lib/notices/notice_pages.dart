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
import '../core/neighborhood_region.dart';
import 'notice_design.dart';
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
    PetPill(
      n['is_public_source'] == true ? '원문 수집' : '공식',
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

// '내 복지관' mockup 2026-10-30: B30–B35 notice detail.
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

  Widget? bottom(BuildContext c, NoticeData n) {
    final phone = '${n['telephone'] ?? ''}'.trim();
    final source = '${n['source_url'] ?? ''}';
    if (n['is_public_source'] == true || (phone.isEmpty && source.isNotEmpty)) {
      return NoticeButton(
        '기관 원문에서 자세히 보기',
        icon: Icons.open_in_new_rounded,
        onTap: () =>
            openSource(c, source, institution: '${n['org_name'] ?? ''}'),
      );
    }
    if (phone.isEmpty) return null;
    return NoticeButton(
      '기관에 전화 문의',
      icon: Icons.phone_outlined,
      onTap: () => callFacility(c, phone),
    );
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<NoticeData>(
    future: data,
    builder: (c, s) {
      final n = s.data;
      return NeighborhoodScreen(
        title: '공지',
        tint: NoticeColors.tint,
        bottom: n == null || s.hasError ? null : bottom(c, n),
        child: s.connectionState != ConnectionState.done
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  NoticeSkeleton(count: 2, label: '공지를 불러오고 있어요'),
                ],
              )
            : s.hasError
            ? ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  NoticeStateCard(
                    error: true,
                    icon: Icons.wifi_off_rounded,
                    title: '공지를 불러오지 못했어요',
                    message: '게시가 끝났거나 잠시 연결이 어려워요.',
                    action: '다시 시도',
                    actionIcon: Icons.refresh_rounded,
                    onAction: () => setState(() {
                      data = repo.detail(widget.id);
                    }),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  _NoticeBody(n!),
                  if ((n['programs'] as List? ?? []).isNotEmpty) ...[
                    const NeighborhoodHeading(
                      '함께 보면 좋아요',
                      color: NoticeColors.blue,
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
                    const NeighborhoodHeading(
                      '시설 위치',
                      color: NoticeColors.blue,
                    ),
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

class _NoticeBody extends StatelessWidget {
  const _NoticeBody(this.n);
  final NoticeData n;
  @override
  Widget build(BuildContext c) {
    final public = n['is_public_source'] == true;
    final phone = '${n['telephone'] ?? ''}'.trim();
    final source = '${n['source_url'] ?? ''}';
    final images = List<String>.from(n['image_paths'] ?? const []);
    final dates = [
      ('게시일', noticeLongDate(n['published_at'] ?? n['created_at'])),
      if (public) ('확인일', noticeLongDate(n['source_verified_at'])),
      if (n['expires_at'] != null) ('게시 종료', noticeLongDate(n['expires_at'])),
    ];
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: NoticeColors.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              NoticeSourceTag(n),
              if (isNewNotice(n)) const NoticeNewBadge(),
              if (n['important'] == true)
                const PetPill(
                  '중요',
                  color: Color(0xFFFFE9E7),
                  ink: Colors.redAccent,
                  fontSize: 13,
                ),
              if (public && n['archived'] == true)
                const PetPill('지난 공지', fontSize: 13),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${n['title']}',
            style: petText(
              24,
              color: NoticeColors.ink,
              weight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: IntrinsicColumnWidth(),
              1: FlexColumnWidth(),
            },
            children: [
              for (final (label, value) in dates)
                TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 14, bottom: 8),
                      child: Text(
                        label,
                        style: petText(16, color: NoticeColors.muted),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        value,
                        style: petText(
                          16,
                          color: NoticeColors.ink,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const Divider(height: 20, color: NoticeColors.line),
          Row(
            children: [
              const InstitutionLogo(size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${n['org_name'] ?? '기관'}',
                      style: petText(
                        17,
                        color: NoticeColors.ink,
                        weight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      public
                          ? '${n['region_sido'] ?? ''} ${n['region_sigungu'] ?? ''}'
                                .trim()
                          : '담당자가 앱에서 직접 올렸어요',
                      style: petText(14, color: NoticeColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (public)
            _box(
              Icons.info_outline_rounded,
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '기관 홈페이지에 올라온 공지의 제목과 게시일이에요.\n'),
                    TextSpan(
                      text: '대상·일정·신청 방법과 접수 여부는 원문에서 확인해 주세요.',
                      style: petText(
                        16,
                        color: NoticeColors.ink,
                        weight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                style: petText(
                  16,
                  color: NoticeColors.text,
                ).copyWith(height: 1.55),
              ),
            )
          else ...[
            if ('${n['body'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 14),
              SelectableText(
                '${n['body']}',
                style: petText(
                  18,
                  color: const Color(0xFF24384C),
                  weight: FontWeight.w500,
                ).copyWith(height: 1.7),
              ),
            ],
            for (final (i, path) in images.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: InkWell(
                  onTap: () => Navigator.push(
                    c,
                    MaterialPageRoute(
                      builder: (_) => PhotoViewer(
                        photos: [for (final p in images) (file: null, path: p)],
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
            if (phone.isNotEmpty)
              _box(
                Icons.phone_outlined,
                Text(
                  '문의 $phone',
                  style: petText(
                    16,
                    color: NoticeColors.text,
                    weight: FontWeight.w800,
                  ),
                ),
              ),
            if (phone.isNotEmpty && source.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => openSource(
                    c,
                    source,
                    institution: '${n['org_name'] ?? ''}',
                  ),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('기관 원문 보기'),
                ),
              ),
          ],
          if (n['reader_count'] != null) ...[
            const SizedBox(height: 12),
            Text(
              '읽은 이웃 ${n['reader_count']}명',
              style: petText(14, color: NoticeColors.muted),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _box(IconData icon, Widget child) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: NoticeColors.soft,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: NoticeColors.blue),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    ),
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

/// B32 → external browser → B33 when the page cannot be opened.
Future<void> openSource(
  BuildContext c,
  String url, {
  String institution = '',
}) async {
  final link = Uri.tryParse(url);
  if (link == null ||
      link.scheme != 'https' ||
      link.host.isEmpty ||
      link.userInfo.isNotEmpty) {
    return;
  }
  final go = await showModalBottomSheet<bool>(
    context: c,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (s) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '기관 홈페이지로 이동해요',
              style: petText(
                21,
                color: NoticeColors.ink,
                weight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '휴대폰 인터넷 창에서 원문이 열려요',
              style: petText(16, color: NoticeColors.muted),
            ),
            const SizedBox(height: 14),
            _InfoRows([
              ('기관', institution.isEmpty ? link.host : institution),
              ('돌아오기', '뒤로 가기를 누르면 앱으로'),
            ]),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: NoticeButton(
                    '취소',
                    secondary: true,
                    onTap: () => Navigator.pop(s, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: NoticeButton(
                    '원문 열기',
                    onTap: () => Navigator.pop(s, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  while (go == true && c.mounted) {
    try {
      if (await launchUrl(link, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      // Shown below as B33.
    }
    if (!c.mounted) return;
    if (!await activityDialog(
      c,
      title: '원문을 열 수 없어요',
      message: '기관 홈페이지가 바뀌었거나\n잠시 접속이 어려워요.',
      action: '다시 시도',
      secondary: '닫기',
      icon: Icons.error_outline_rounded,
      color: PetColors.orange,
    )) {
      return;
    }
  }
}

class _InfoRows extends StatelessWidget {
  const _InfoRows(this.rows);
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: NoticeColors.soft,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        for (final (i, (label, value)) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1, color: NoticeColors.line),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: petText(15, color: NoticeColors.muted)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: petText(
                      16,
                      color: NoticeColors.ink,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

String _shortSido(String sido) =>
    sido.replaceFirst(RegExp(r'(특별자치시|특별자치도|특별시|광역시)$'), '');

/// B20–B26 '내 복지관 소식' (preferredOnly) and the 다른 소식 lists
/// (우리 동네 기관 소식 / 전체 지역 소식 / 지난 공개 공지).
class NoticeListPage extends StatefulWidget {
  const NoticeListPage({
    super.key,
    this.repository,
    this.preferredOnly = false,
    this.allRegions = false,
    this.archive = false,
  });
  final NoticeRepository? repository;
  final bool preferredOnly, allRegions, archive;
  @override
  State<NoticeListPage> createState() => _ListState();
}

class _ListState extends State<NoticeListPage> {
  late final repo = widget.repository ?? NoticeRepository();
  late final bool mine = widget.preferredOnly;
  late bool allRegions = widget.allRegions, archive = widget.archive;
  NoticeData? institution;
  NeighborhoodRegion? region;
  String kind = '전체';
  int visibleCount = 30;
  late Future<List<NoticeData>> data = load();

  Future<List<NoticeData>> load() async {
    if (mine) {
      final found = await repo.preferredInstitution();
      if (mounted) setState(() => institution = found);
      return found == null ? [] : repo.institutionFeed(found, archive: archive);
    }
    if (region == null) {
      repo.currentRegion().then((r) {
        if (mounted) setState(() => region = r);
      }, onError: (_) {});
    }
    return repo.browse(archive: archive, allRegions: allRegions);
  }

  Future<void> reload() async {
    final f = load();
    setState(() {
      data = f;
      visibleCount = 30;
    });
    try {
      await f;
    } catch (_) {}
  }

  void showArchive(bool value) {
    if (archive == value) return;
    archive = value;
    reload();
  }

  Future<void> choose() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NoticeInstitutionPicker(repository: repo, current: institution),
      ),
    );
    if (saved == true && mounted) await reload();
  }

  Future<void> otherNews() async {
    NeighborhoodRegion? here;
    try {
      here = await repo.currentRegion().timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (!mounted) return;
    final pick = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (s) {
        Widget option(
          int value,
          IconData icon,
          Color tint,
          Color ink,
          String title,
          String subtitle,
        ) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pop(s, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: ink),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: petText(
                          18,
                          color: NoticeColors.ink,
                          weight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: petText(15, color: NoticeColors.muted),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: NoticeColors.muted,
                ),
              ],
            ),
          ),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '다른 소식 보기',
                  style: petText(
                    21,
                    color: NoticeColors.ink,
                    weight: FontWeight.w900,
                  ),
                ),
                Text(
                  '필요할 때만 열어서 골라요',
                  style: petText(15, color: NoticeColors.muted),
                ),
                const SizedBox(height: 8),
                option(
                  0,
                  Icons.place_outlined,
                  const Color(0xFFE2F6EC),
                  const Color(0xFF14633F),
                  '우리 동네 기관 소식',
                  here == null
                      ? '지금 지역의 복지관·주민센터'
                      : '${_shortSido(here.sido)} ${here.sigungu}의 복지관·주민센터',
                ),
                const Divider(height: 1, color: NoticeColors.line),
                option(
                  1,
                  Icons.map_outlined,
                  const Color(0xFFE6F2FB),
                  NoticeColors.blue,
                  '전체 지역 소식',
                  '지역과 기관 종류를 골라 보기',
                ),
                const Divider(height: 1, color: NoticeColors.line),
                option(
                  2,
                  Icons.description_outlined,
                  const Color(0xFFEEECFF),
                  PetColors.purple,
                  '지난 공개 공지',
                  '두 달이 지난 공지',
                ),
                const SizedBox(height: 12),
                NoticeButton(
                  '닫기',
                  secondary: true,
                  onTap: () => Navigator.pop(s),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (pick == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoticeListPage(
          repository: repo,
          allRegions: pick == 1,
          archive: pick == 2,
        ),
      ),
    );
  }

  Widget pill(
    String label, {
    required bool selected,
    required VoidCallback onTap,
    bool dark = false,
  }) => Semantics(
    container: true,
    selected: selected,
    button: true,
    excludeSemantics: true,
    label: label,
    child: Material(
      color: selected
          ? (dark ? NoticeColors.ink : NoticeColors.blue)
          : Colors.white,
      shape: const StadiumBorder(),
      elevation: selected ? 0 : 1,
      shadowColor: const Color(0x330F2D50),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: petText(
                  16,
                  color: selected ? Colors.white : NoticeColors.text,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget scrollRow(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    clipBehavior: Clip.none,
    child: Row(
      children: [
        for (final (i, w) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          w,
        ],
      ],
    ),
  );

  List<Widget> header() => [
    if (mine && institution != null)
      Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: NoticeColors.shadow,
        ),
        child: Row(
          children: [
            const InstitutionLogo(size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '내 복지관',
                    style: petText(
                      13,
                      color: NoticeColors.label,
                      weight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${institution!['institution_name']}',
                    style: petText(
                      19,
                      color: NoticeColors.ink,
                      weight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            NoticeChipButton('변경', onTap: choose),
          ],
        ),
      ),
    if (!mine || institution != null)
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  pill(
                    '새 소식',
                    selected: !archive,
                    dark: true,
                    onTap: () => showArchive(false),
                  ),
                  pill(
                    '지난 공지',
                    selected: archive,
                    dark: true,
                    onTap: () => showArchive(true),
                  ),
                ],
              ),
            ),
            if (mine)
              Semantics(
                container: true,
                button: true,
                child: Material(
                  color: NoticeColors.sky,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: otherNews,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.expand_more_rounded,
                              color: NoticeColors.label,
                            ),
                            Text(
                              '다른 소식',
                              style: petText(
                                15,
                                color: NoticeColors.label,
                                weight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    if (!mine) ...[
      const SizedBox(height: 8),
      scrollRow([
        pill(
          region == null ? '우리 동네' : '우리 동네 · ${region!.sigungu}',
          selected: !allRegions,
          onTap: () {
            if (!allRegions) return;
            allRegions = false;
            reload();
          },
        ),
        pill(
          '전체 지역',
          selected: allRegions,
          onTap: () {
            if (allRegions) return;
            allRegions = true;
            reload();
          },
        ),
      ]),
      const SizedBox(height: 8),
      scrollRow([
        for (final k in _noticeKinds)
          pill(k, selected: kind == k, onTap: () => setState(() => kind = k)),
      ]),
    ],
  ];

  Widget label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
    child: Text(
      text,
      style: petText(
        16,
        color: const Color(0xFF5A6B7B),
        weight: FontWeight.w900,
      ),
    ),
  );

  void open(NoticeData n) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => NoticeDetailPage(id: '${n['id']}', repository: repo),
    ),
  );

  List<Widget> content(AsyncSnapshot<List<NoticeData>> s) {
    if (s.connectionState != ConnectionState.done) {
      return [
        const SizedBox(height: 8),
        const NoticeSkeleton(label: '소식을 불러오고 있어요'),
      ];
    }
    if (s.hasError) {
      return [
        const SizedBox(height: 8),
        NoticeStateCard(
          error: true,
          icon: Icons.wifi_off_rounded,
          title: '소식을 불러오지 못했어요',
          message: '잠시 뒤 다시 시도해 주세요',
          action: '다시 시도',
          actionIcon: Icons.refresh_rounded,
          onAction: reload,
        ),
      ];
    }
    if (mine && institution == null) {
      return [
        const SizedBox(height: 8),
        NoticeStateCard(
          icon: Icons.apartment_rounded,
          title: '자주 가는 복지관을 지정해 주세요',
          message: '지정한 복지관의 소식만 모아 보여 드려요',
          action: '내 복지관 지정하기',
          actionIcon: Icons.add_rounded,
          onAction: choose,
          secondary: '다른 기관 소식 보기',
          onSecondary: otherNews,
        ),
      ];
    }
    final rows = [
      for (final n in s.data!)
        if (kind == '전체' || _kind(n) == kind) n,
    ];
    if (rows.isEmpty) {
      return [
        const SizedBox(height: 8),
        archive
            ? NoticeStateCard(
                icon: Icons.history_rounded,
                title: '지난 공지가 없어요',
                message: '두 달이 지난 공지가 여기에 모여요',
                action: '새 소식 보기',
                onAction: () => showArchive(false),
                secondary: mine ? '다른 기관 소식 보기' : null,
                onSecondary: otherNews,
              )
            : NoticeStateCard(
                icon: Icons.notifications_none_rounded,
                title: '아직 새 소식이 없어요',
                message: '새 공지가 올라오면 여기에 모아 드려요',
                action: '지난 공지 보기',
                onAction: () => showArchive(true),
                secondary: mine ? '다른 기관 소식 보기' : null,
                onSecondary: otherNews,
              ),
      ];
    }
    final shown = rows.take(visibleCount).toList();
    final recent = archive ? <NoticeData>[] : shown.where(isNewNotice).toList();
    final older = [
      for (final n in shown)
        if (!recent.contains(n)) n,
    ];
    Widget card(NoticeData n) => NoticeListCard(
      n,
      showInstitution: !mine,
      showNew: !archive,
      onTap: () => open(n),
    );
    return [
      if (recent.isNotEmpty) ...[
        label('최근 일주일'),
        for (final n in recent) card(n),
      ],
      if (older.isNotEmpty) ...[
        if (recent.isNotEmpty) label('그 이전') else const SizedBox(height: 10),
        for (final n in older) card(n),
      ],
      if (rows.length > visibleCount)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: NoticeButton(
            '공지 더 보기',
            secondary: true,
            onTap: () => setState(() => visibleCount += 30),
          ),
        ),
      if (rows.any((n) => n['is_public_source'] == true))
        const NoticeHint('‘홈페이지 원문’은 기관 홈페이지에서 모은 공지예요. 자세한 내용은 원문에서 확인해 주세요.'),
    ];
  }

  @override
  Widget build(BuildContext c) => NeighborhoodScreen(
    title: mine
        ? '내 복지관 소식'
        : archive
        ? '지난 공개 공지'
        : allRegions
        ? '전체 지역 소식'
        : '우리 동네 기관 소식',
    tint: NoticeColors.tint,
    child: FutureBuilder<List<NoticeData>>(
      future: data,
      builder: (c, s) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          children: [...header(), ...content(s)],
        ),
      ),
    ),
  );
}

typedef _MyNews = ({NoticeData? institution, List<NoticeData>? notices});

/// B01–B05 home card: choose once, then this institution's 새 소식.
class MyInstitutionNoticeCard extends StatefulWidget {
  const MyInstitutionNoticeCard({
    super.key,
    required this.repository,
    this.refreshKey,
  });
  final NoticeRepository repository;

  /// Reloads the card when the home screen refreshes.
  final Object? refreshKey;
  @override
  State<MyInstitutionNoticeCard> createState() => _MyInstitutionCardState();
}

class _MyInstitutionCardState extends State<MyInstitutionNoticeCard> {
  late int revision = widget.repository.preferenceRevision;
  late Future<_MyNews> news = load();

  Future<_MyNews> load() async {
    final institution = await widget.repository.preferredInstitution();
    if (institution == null) return (institution: null, notices: null);
    try {
      return (
        institution: institution,
        notices: await widget.repository
            .institutionFeed(institution)
            .timeout(const Duration(seconds: 12)),
      );
    } catch (_) {
      return (institution: institution, notices: null);
    }
  }

  void refresh() => setState(() {
    revision = widget.repository.preferenceRevision;
    news = load();
  });

  @override
  void didUpdateWidget(covariant MyInstitutionNoticeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.refreshKey != widget.refreshKey ||
        revision != widget.repository.preferenceRevision) {
      revision = widget.repository.preferenceRevision;
      news = load();
    }
  }

  Future<void> push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) refresh();
  }

  Future<void> choose(NoticeData? current) => push(
    NoticeInstitutionPicker(repository: widget.repository, current: current),
  );

  Widget heading(NoticeData? institution, String? note) => Row(
    children: [
      InstitutionLogo(soft: institution == null),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: institution == null
              ? [
                  Text(
                    '내 복지관',
                    style: petText(
                      20,
                      color: NoticeColors.ink,
                      weight: FontWeight.w900,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note,
                      style: petText(15, color: const Color(0xFF5A6B7B)),
                    ),
                ]
              : [
                  Text(
                    '내 복지관',
                    style: petText(
                      14,
                      color: NoticeColors.label,
                      weight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${institution['institution_name']}',
                    style: petText(
                      20,
                      color: NoticeColors.ink,
                      weight: FontWeight.w900,
                    ),
                  ),
                ],
        ),
      ),
      if (institution != null) ...[
        const SizedBox(width: 8),
        NoticeChipButton('변경', onTap: () => choose(institution)),
      ],
    ],
  );

  Widget note(IconData icon, String text) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: NoticeColors.soft,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20, color: NoticeColors.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: petText(16, color: const Color(0xFF4A5B6B))),
        ),
      ],
    ),
  );

  Widget latest(List<NoticeData> rows) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE6EEF5)),
    ),
    child: Column(
      children: [
        for (final (i, n) in rows.indexed) ...[
          if (i > 0) const Divider(height: 1, color: NoticeColors.line),
          InkWell(
            onTap: () => push(
              NoticeDetailPage(id: '${n['id']}', repository: widget.repository),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: NoticeColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${n['title']}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: petText(
                          17,
                          color: NoticeColors.ink,
                          weight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      noticeShortDate(n['published_at']),
                      style: petText(14, color: const Color(0xFF7A8794)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  @override
  Widget build(BuildContext c) => FutureBuilder<_MyNews>(
    future: news,
    builder: (c, s) {
      final loading = s.connectionState != ConnectionState.done;
      final institution = s.data?.institution;
      final notices = s.data?.notices;
      final fresh = [
        for (final n in notices ?? const <NoticeData>[])
          if (isNewNotice(n)) n,
      ];
      final children = <Widget>[
        if (loading)
          heading(null, '지정한 복지관을 확인하고 있어요')
        else if (s.hasError) ...[
          heading(null, '저장한 복지관을 확인하지 못했어요'),
          const SizedBox(height: 14),
          NoticeButton(
            '다시 불러오기',
            secondary: true,
            icon: Icons.refresh_rounded,
            onTap: refresh,
          ),
        ] else if (institution == null) ...[
          heading(null, '자주 가는 복지관 소식을 모아보세요'),
          const SizedBox(height: 14),
          NoticeButton(
            '내 복지관 지정하기',
            icon: Icons.add_rounded,
            onTap: () => choose(null),
          ),
        ] else ...[
          heading(institution, null),
          if (notices == null) ...[
            note(Icons.wifi_off_rounded, '소식을 불러오지 못했어요'),
            const SizedBox(height: 14),
            NoticeButton(
              '다시 불러오기',
              secondary: true,
              icon: Icons.refresh_rounded,
              onTap: refresh,
            ),
          ] else if (fresh.isEmpty) ...[
            note(Icons.check_rounded, '새 소식이 없어요\n지난 공지는 소식 보기에서 볼 수 있어요'),
            const SizedBox(height: 14),
            NoticeButton(
              '소식 보기 ›',
              secondary: true,
              onTap: () => push(
                NoticeListPage(
                  repository: widget.repository,
                  preferredOnly: true,
                ),
              ),
            ),
          ] else ...[
            latest(fresh.take(2).toList()),
            const SizedBox(height: 14),
            NoticeButton(
              '소식 보기',
              badge: '새 소식 ${fresh.length}',
              onTap: () => push(
                NoticeListPage(
                  repository: widget.repository,
                  preferredOnly: true,
                ),
              ),
            ),
          ],
        ],
      ];
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF3F9FE)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .9)),
          boxShadow: NoticeColors.shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -50,
              top: -60,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0xFFE3F1FC), Color(0x00E3F1FC)],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// B10–B19: pick (or change) the one usual institution.
class NoticeInstitutionPicker extends StatefulWidget {
  const NoticeInstitutionPicker({
    super.key,
    required this.repository,
    this.current,
  });
  final NoticeRepository repository;

  /// The institution chosen now; switches the screen to 변경 mode.
  final NoticeData? current;
  @override
  State<NoticeInstitutionPicker> createState() =>
      _NoticeInstitutionPickerState();
}

class _NoticeInstitutionPickerState extends State<NoticeInstitutionPicker> {
  late Future<List<NoticeData>> institutions = load();
  final search = TextEditingController();
  NoticeData? selected;
  bool busy = false;

  bool get changing => widget.current != null;
  bool same(NoticeData? a, NoticeData? b) =>
      a != null &&
      b != null &&
      institutionKey(a['institution_name']) ==
          institutionKey(b['institution_name']) &&
      a['region_sido'] == b['region_sido'] &&
      a['region_sigungu'] == b['region_sigungu'];

  /// Institutions in the browsing district come first.
  Future<List<NoticeData>> load() async {
    final rows = await widget.repository.institutions();
    NeighborhoodRegion? here;
    try {
      here = await widget.repository.currentRegion().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}
    if (here == null) return rows;
    bool near(NoticeData n) =>
        n['region_sido'] == here!.sido && n['region_sigungu'] == here.sigungu;
    return [...rows.where(near), ...rows.where((n) => !near(n))];
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final choice = selected;
    if (busy || choice == null || same(choice, widget.current)) return;
    if (changing &&
        !await activityDialog(
          context,
          title: '내 복지관을 바꿀까요?',
          message: '홈과 소식 목록이 새 기관으로 바뀌어요.',
          icon: Icons.apartment_rounded,
          color: NoticeColors.blue,
          rows: [
            ('지금', '${widget.current!['institution_name']}'),
            ('바꿀 곳', '${choice['institution_name']}'),
          ],
          action: '바꾸기',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.selectInstitution(choice);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      showNoticeToast(messenger, changing ? '내 복지관을 바꿨어요' : '내 복지관으로 지정했어요');
    } catch (_) {
      if (mounted) {
        setState(() => busy = false);
        await activityFailure(
          context,
          title: '내 복지관을 저장하지 못했어요',
          message: '선택한 내용은 유지돼요. 잠시 후 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Search match highlighted like the mockup's yellow marker.
  Widget marked(String text, String query, TextStyle style) {
    final at = query.isEmpty ? -1 : text.indexOf(query);
    if (at < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, at)),
          TextSpan(
            text: text.substring(at, at + query.length),
            style: const TextStyle(backgroundColor: Color(0xFFFFF1B8)),
          ),
          TextSpan(text: text.substring(at + query.length)),
        ],
      ),
    );
  }

  Widget option(NoticeData n, String query) {
    final on = identical(selected, n);
    final now = same(n, widget.current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        selected: on,
        button: true,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: on ? NoticeColors.blue : Colors.transparent,
              width: 2,
            ),
          ),
          elevation: on ? 3 : 1,
          shadowColor: const Color(0x330F2D50),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: busy ? null : () => setState(() => selected = n),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: on
                  ? const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.white, Color(0xFFEEF6FD)],
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: on ? NoticeColors.gradient : null,
                      border: on
                          ? null
                          : Border.all(
                              color: const Color(0xFFB9C9D8),
                              width: 3,
                            ),
                    ),
                    child: on
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            marked(
                              '${n['institution_name']}',
                              query,
                              petText(
                                19,
                                color: NoticeColors.ink,
                                weight: FontWeight.w900,
                              ),
                            ),
                            if (now)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE1F0FB),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  '지금 내 복지관',
                                  style: petText(
                                    12,
                                    color: NoticeColors.label,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        marked(
                          '${n['region_sido']} ${n['region_sigungu']}',
                          query,
                          petText(15, color: const Color(0xFF4A5B6B)),
                        ),
                        if (n['address'] != null)
                          Text(
                            '${n['address']}',
                            style: petText(
                              14,
                              color: const Color(0xFF7A8794),
                              weight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget cta() {
    final choice = selected;
    if (busy) {
      return const NoticeButton('저장하는 중…', busy: true, onTap: null);
    }
    if (choice == null) {
      return const NoticeButton('복지관을 골라 주세요', onTap: null);
    }
    if (same(choice, widget.current)) {
      return const NoticeButton('지금 내 복지관이에요', onTap: null);
    }
    return NoticeButton(changing ? '이곳으로 변경' : '내 복지관으로 지정', onTap: save);
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: NeighborhoodScreen(
      title: changing ? '내 복지관 변경' : '내 복지관 지정',
      subtitle: '자주 이용하는 곳 한 곳을 골라 주세요',
      tint: NoticeColors.tint,
      bottom: cta(),
      child: FutureBuilder<List<NoticeData>>(
        future: institutions,
        builder: (c, s) {
          final raw = search.text.trim();
          final q = raw.replaceAll(' ', '').toLowerCase();
          final rows = (s.data ?? [])
              .where(
                (n) =>
                    '${n['institution_name']}${n['region_sido']}${n['region_sigungu']}${n['address'] ?? ''}'
                        .replaceAll(' ', '')
                        .toLowerCase()
                        .contains(q),
              )
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              TextField(
                controller: search,
                onChanged: (_) => setState(() {}),
                style: petText(
                  18,
                  color: NoticeColors.ink,
                  weight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  labelText: '복지관 이름·지역 검색',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: raw.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '검색어 지우기',
                          onPressed: () => setState(search.clear),
                          icon: const Icon(Icons.close_rounded),
                        ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: Color(0xFFE3ECF4),
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: NoticeColors.blue,
                      width: 2,
                    ),
                  ),
                ),
              ),
              if (s.connectionState != ConnectionState.done) ...[
                const SizedBox(height: 14),
                const NoticeSkeleton(label: '복지관 목록을 불러오고 있어요'),
              ] else if (s.hasError) ...[
                const SizedBox(height: 16),
                NoticeStateCard(
                  error: true,
                  icon: Icons.wifi_off_rounded,
                  title: '복지관 목록을 불러오지 못했어요',
                  message: '인터넷 연결을 확인한 뒤\n다시 시도해 주세요',
                  action: '다시 시도',
                  actionIcon: Icons.refresh_rounded,
                  onAction: () => setState(() {
                    institutions = load();
                  }),
                ),
              ] else if (rows.isEmpty) ...[
                const SizedBox(height: 16),
                NoticeStateCard(
                  icon: Icons.search_rounded,
                  title: '찾는 복지관이 없어요',
                  message: '이름을 짧게 줄이거나\n‘동작구’처럼 지역으로 찾아보세요',
                  secondary: '검색어 지우기',
                  onSecondary: () => setState(search.clear),
                ),
                const NoticeHint('아직 소식을 모으지 않는 기관은 목록에 없을 수 있어요.'),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: raw.isEmpty ? '복지관 ' : '검색 결과 '),
                        TextSpan(
                          text: '${rows.length}',
                          style: const TextStyle(color: NoticeColors.blue),
                        ),
                        const TextSpan(text: '곳'),
                      ],
                    ),
                    style: petText(
                      15,
                      color: const Color(0xFF5A6B7B),
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                for (final n in rows) option(n, raw),
                const NoticeHint('지정해도 이용 자격이 정해지지 않아요. 이용 대상은 기관에 확인해 주세요.'),
              ],
            ],
          );
        },
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
                : '우리 동네 기관 소식과 이 기관을 내 복지관으로 지정한 이웃의 홈에 표시돼요.')
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

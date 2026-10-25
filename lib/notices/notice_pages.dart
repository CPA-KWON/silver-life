import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/region_picker.dart';
import '../core/korea_regions.dart';
import '../pet/pet_design.dart';
import 'notice_repository.dart';

String noticeDate(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  return d == null
      ? ''
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

String noticeStatus(NoticeData n) => n['published'] != true
    ? '비공개'
    : n['expires_at'] != null &&
          DateTime.parse(n['expires_at']).isBefore(DateTime.now())
    ? '게시 종료'
    : '게시 중';

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
  Widget build(BuildContext c) => PetScreen(
    colors: const [PetColors.background, PetColors.background],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PetHeader('기관 공지'),
        FutureBuilder<NoticeData>(
          future: data,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (s.hasError) {
              return PetCard(
                child: Column(
                  children: [
                    Text('게시가 종료됐거나 공지를 불러오지 못했어요.', style: petText(18)),
                    TextButton(
                      onPressed: () => setState(() {
                        data = repo.detail(widget.id);
                      }),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              );
            }
            final n = s.data!;
            final link = Uri.tryParse('${n['source_url'] ?? ''}');
            return PetCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: PetPill(
                      '기관 공지',
                      color: PetColors.yellow,
                      ink: PetColors.orange,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('${n['title']}', style: petText(25)),
                  const SizedBox(height: 12),
                  Text(
                    '${n['org_name']} · ${n['region_sido']} ${n['region_sigungu']}',
                    style: petText(17, color: PetColors.secondary),
                  ),
                  Text(
                    '게시 ${noticeDate(n['published_at'] ?? n['created_at'])}${n['expires_at'] == null ? '' : ' · 종료 ${noticeDate(n['expires_at'])}'}',
                    style: petText(16, color: PetColors.secondary),
                  ),
                  const Divider(height: 32),
                  SelectableText(
                    '${n['body']}',
                    style: petText(19, weight: FontWeight.w500),
                  ),
                  if (link != null &&
                      link.scheme == 'https' &&
                      link.host.isNotEmpty &&
                      link.userInfo.isEmpty) ...[
                    const SizedBox(height: 24),
                    PetPrimary(
                      '원문 보기 · ${link.host}',
                      light: true,
                      onTap: () async {
                        try {
                          if (!await launchUrl(
                            link,
                            mode: LaunchMode.externalApplication,
                          )) {
                            throw StateError('open');
                          }
                        } catch (_) {
                          if (c.mounted) {
                            await petDialog(
                              c,
                              title: '원문을 열지 못했어요',
                              message: link.toString(),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    ),
  );
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
  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('우리 동네 기관 공지')),
    body: FutureBuilder<List<NoticeData>>(
      future: data,
      builder: (c, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (s.hasError)
              PetCard(
                child: Column(
                  children: [
                    Text('기관 공지를 불러오지 못했어요.', style: petText(18)),
                    TextButton(
                      onPressed: () => setState(() {
                        data = repo.feed();
                      }),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              )
            else if (s.data!.isEmpty)
              PetCard(child: Text('아직 등록된 기관 공지가 없어요.', style: petText(18)))
            else
              for (final n in s.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PetCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${n['title']}', style: petText(20)),
                      subtitle: Text(
                        '${n['org_name']} · ${noticeDate(n['published_at'])}',
                        style: petText(16, color: PetColors.secondary),
                      ),
                      onTap: () => Navigator.push(
                        c,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              NoticeDetailPage(id: n['id'], repository: repo),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        );
      },
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
  bool busy = false;
  Future<void> reload() async {
    if (mounted) {
      setState(() {
        data = repo.managed();
      });
    }
  }

  Future<void> edit([NoticeData? n]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NoticeForm(
          organizations: widget.organizations,
          notice: n,
          repository: repo,
        ),
      ),
    );
    if (mounted) await reload();
  }

  Future<void> publish(NoticeData n) async {
    final value = n['published'] != true;
    if (!await petDialog(
      context,
      title: value ? '이 공지를 게시할까요?' : '공지 게시를 중지할까요?',
      message: value
          ? '선택한 지역의 홈에 기관명과 함께 표시돼요.'
          : '홈에서는 내려가고 기관 관리에는 기록이 남아요.',
      action: value ? '게시하기' : '게시 중지',
      secondary: '취소',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await repo.publish(n['id'], value);
      await reload();
    } catch (_) {
      if (mounted) {
        await petDialog(
          context,
          title: '처리하지 못했어요',
          message: '기관 권한과 게시 종료일을 확인하고 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('기관 공지 관리')),
    body: RefreshIndicator(
      onRefresh: reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          PetPrimary(
            '공지 작성',
            onTap: busy || widget.organizations.isEmpty ? null : () => edit(),
          ),
          const SizedBox(height: 16),
          Text(
            '먼저 비공개로 저장하고, 내용을 확인한 뒤 게시해요.',
            style: petText(17, color: PetColors.secondary),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<NoticeData>>(
            future: data,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) {
                return PetCard(
                  child: Column(
                    children: [
                      Text('기관 공지 기능을 불러오지 못했어요.', style: petText(18)),
                      TextButton(onPressed: reload, child: const Text('다시 시도')),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.data!.isEmpty)
                    PetCard(child: Text('등록한 기관 공지가 없어요.', style: petText(18))),
                  for (final n in s.data!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: PetCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                PetPill(noticeStatus(n)),
                                Text(
                                  '${n['org_name']}',
                                  style: petText(
                                    16,
                                    color: PetColors.secondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text('${n['title']}', style: petText(21)),
                            Text(
                              '${n['region_sido']} ${n['region_sigungu']}',
                              style: petText(17, color: PetColors.secondary),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: busy ? null : () => edit(n),
                                  child: const Text('수정'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.push(
                                    c,
                                    MaterialPageRoute<void>(
                                      builder: (_) => NoticeDetailPage(
                                        id: n['id'],
                                        repository: repo,
                                      ),
                                    ),
                                  ),
                                  child: const Text('내용 보기'),
                                ),
                                FilledButton(
                                  onPressed: busy ? null : () => publish(n),
                                  child: Text(
                                    n['published'] == true ? '게시 중지' : '게시하기',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
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
  late final title = TextEditingController(text: widget.notice?['title']);
  late final body = TextEditingController(text: widget.notice?['body']);
  late final url = TextEditingController(text: widget.notice?['source_url']);
  late final repo = widget.repository ?? NoticeRepository();
  late String org =
      widget.notice?['org_id'] ?? widget.organizations.first['id'];
  late String sido = widget.notice?['region_sido'] ?? kKoreaRegions.keys.first;
  late String district =
      widget.notice?['region_sigungu'] ?? kKoreaRegions[sido]!.first;
  DateTime? end;
  bool touched = false, busy = false;
  @override
  void initState() {
    super.initState();
    end = DateTime.tryParse('${widget.notice?['expires_at']}')?.toLocal();
    if (widget.notice == null) loadRegion();
  }

  Future<void> loadRegion() async {
    try {
      final r = await repo.region();
      if (mounted && !touched) {
        setState(() {
          final province = r['region_sido'];
          if (kKoreaRegions.containsKey(province)) {
            sido = province;
            district = kKoreaRegions[sido]!.contains(r['region_sigungu'])
                ? r['region_sigungu']
                : kKoreaRegions[sido]!.first;
          }
        });
      }
    } catch (_) {
      /* Visible region picker remains editable. */
    }
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    url.dispose();
    super.dispose();
  }

  Future<void> pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          end != null &&
              end!.isAfter(today) &&
              end!.isBefore(today.add(const Duration(days: 730)))
          ? end!
          : today.add(const Duration(days: 30)),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: today.add(const Duration(days: 730)),
    );
    if (picked != null && mounted) {
      setState(
        () => end = DateTime(
          picked.year,
          picked.month,
          picked.day + 1,
        ).subtract(const Duration(seconds: 1)),
      );
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await repo.save({
        'org_id': org,
        'title': title.text.trim(),
        'body': body.text.trim(),
        'source_url': url.text.trim(),
        'region_sido': sido,
        'region_sigungu': district,
        'expires_at': end?.toUtc().toIso8601String(),
      }, id: widget.notice?['id']);
      if (mounted) {
        await petDialog(
          context,
          title: '공지를 저장했어요',
          message: widget.notice == null
              ? '아직 비공개예요. 관리 화면에서 내용을 확인하고 게시해주세요.'
              : '변경 내용을 저장했어요.',
        );
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        await petDialog(
          context,
          title: '저장하지 못했어요',
          message: '기관 권한과 입력 내용을 확인한 뒤 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(
      title: Text(widget.notice == null ? '기관 공지 작성' : '기관 공지 수정'),
    ),
    body: widget.organizations.isEmpty
        ? const Center(child: Text('승인된 기관 담당자만 공지를 작성할 수 있어요.'))
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: org,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '게시 기관'),
                  items: [
                    for (final o in widget.organizations)
                      DropdownMenuItem(
                        value: '${o['id']}',
                        child: Text('${o['name']}'),
                      ),
                  ],
                  onChanged: widget.notice != null
                      ? null
                      : (v) => setState(() => org = v!),
                ),
                const SizedBox(height: 16),
                Text('공지 대상 지역', style: petText(19)),
                const SizedBox(height: 8),
                RegionPicker(
                  key: ValueKey('$sido/$district'),
                  initialSido: sido,
                  initialSigungu: district,
                  onChanged: (a, b) {
                    touched = true;
                    setState(() {
                      sido = a;
                      district = b;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(labelText: '제목'),
                  maxLength: 100,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '제목을 입력해주세요.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: body,
                  decoration: const InputDecoration(labelText: '공지 내용'),
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 5000,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '내용을 입력해주세요.' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: url,
                  decoration: const InputDecoration(
                    labelText: '원문 링크 (선택)',
                    hintText: 'https://',
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final u = Uri.tryParse(v.trim());
                    return u != null &&
                            u.scheme == 'https' &&
                            u.host.contains('.') &&
                            u.userInfo.isEmpty
                        ? null
                        : 'https://로 시작하는 원문 주소를 입력해주세요.';
                  },
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    end == null
                        ? '게시 종료일 선택 (선택)'
                        : '게시 종료일 ${noticeDate(end!.toIso8601String())}',
                  ),
                ),
                if (end != null)
                  TextButton(
                    onPressed: () => setState(() => end = null),
                    child: const Text('종료일 없이 게시'),
                  ),
                const SizedBox(height: 16),
                PetPrimary(busy ? '저장 중' : '저장하기', onTap: busy ? null : save),
                const SizedBox(height: 16),
              ],
            ),
          ),
  );
}

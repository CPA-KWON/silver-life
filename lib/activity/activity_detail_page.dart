import 'package:flutter/material.dart';

import '../pet/pet_design.dart';
import '../core/phone_call.dart';
import 'activity_design.dart';
import 'activity_repository.dart';
import 'activity_map_page.dart';
import 'activity_hub_page.dart';
import 'activity_program_card.dart';
import 'activity_support_page.dart';

class ActivityDetailPage extends StatefulWidget {
  const ActivityDetailPage({
    super.key,
    required this.programId,
    this.repository,
    this.mapPlaceholder,
  });
  final String programId;
  final ActivityRepository? repository;
  final Widget? mapPlaceholder;
  @override
  State<ActivityDetailPage> createState() => _DetailState();
}

class _DetailState extends State<ActivityDetailPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future = load();
  bool busy = false,
      favoriteBusy = false,
      favorite = false,
      favoriteAvailable = true;
  Future<ActivityData> load() async {
    final detail = await repo.detail(widget.programId);
    final home = await repo.home();
    try {
      favorite = await repo.isFavorite(widget.programId);
      favoriteAvailable = true;
    } catch (_) {
      favoriteAvailable = false;
    }
    return {...detail, 'experiences': home['experiences']};
  }

  Future<void> reload() async {
    if (!mounted) return;
    final f = load();
    setState(() {
      future = f;
    });
    try {
      await f;
    } catch (_) {}
  }

  Future<void> toggleFavorite() async {
    if (favoriteBusy) return;
    if (!favoriteAvailable) {
      await activityFailure(
        context,
        title: '관심 프로그램 저장 설정이 필요해요',
        message: '추가 서버 설정이 완료되면 관심 프로그램을 저장할 수 있어요. 프로그램 신청은 계속 이용할 수 있어요.',
      );
      return;
    }
    setState(() => favoriteBusy = true);
    try {
      await repo.favorite(widget.programId, !favorite);
      if (mounted) setState(() => favorite = !favorite);
    } catch (_) {
      if (mounted) await activityFailure(context, title: '관심 프로그램을 저장하지 못했어요');
    } finally {
      if (mounted) setState(() => favoriteBusy = false);
    }
  }

  Future<void> act(ActivityData d, {required bool cancel}) async {
    if (busy) return;
    final p = Map<String, dynamic>.from(d['program']);
    if (!await activityDialog(
      context,
      title: cancel ? '신청을 취소할까요?' : '${p['title']}을\n신청할까요?',
      message: cancel
          ? '취소하면 자리가 다른 분께 넘어가요. 다시 신청할 때 자리가 없을 수 있어요.'
          : '기관이 확인하면 신청 상태가 바뀌어요.\n실제 납부 방법은 기관 안내를 확인해 주세요.',
      action: cancel ? '신청 취소하기' : '신청하기',
      secondary: cancel ? '그대로 두기' : '취소',
      color: cancel ? PetColors.orange : ActivityColors.blue,
      icon: cancel ? Icons.error_outline : Icons.confirmation_number_outlined,
      rows: cancel
          ? []
          : [
              ('첫 활동', activityShortDate(p['starts_at'])),
              ('장소', '${p['place_name']}'),
              ('예상 참여비', activityMoney(d['quote'])),
            ],
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      if (cancel) {
        await repo.cancel(d['application']['id']);
      } else {
        await repo.apply(widget.programId);
      }
      await reload();
      if (!mounted) return;
      setState(() => busy = false);
      if (cancel) {
        await activityDialog(
          context,
          title: '신청을 취소했어요',
          message: '언제든 다시 신청할 수 있어요.',
          icon: Icons.check,
          secondary: '닫기',
        );
      } else {
        final fresh = await repo.detail(widget.programId);
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ActivityReceiptPage(
              program: Map<String, dynamic>.from(fresh['program']),
              repository: repo,
              support: false,
              application: fresh['application'],
            ),
          ),
        );
        if (mounted) await reload();
      }
    } catch (_) {
      await reload();
      if (mounted) {
        await activityFailure(
          context,
          title: cancel ? '취소 상태를 확인해 주세요' : '신청 상태를 확인해 주세요',
          message: '요청 결과를 확인하지 못했어요. 상세 화면과 나의 활동을 새로 확인해 주세요. 모집 마감이나 정원 초과일 수도 있어요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> support(ActivityData d) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ActivitySupportPage(
          program: Map<String, dynamic>.from(d['program']),
          repository: repo,
        ),
      ),
    );
    if (mounted) await reload();
  }

  Widget infoRow(
    IconData icon,
    String title,
    Widget child, {
    bool divider = true,
  }) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F1FC),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, color: ActivityColors.blue, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: petText(15, color: ActivityColors.muted)),
                  const SizedBox(height: 5),
                  child,
                ],
              ),
            ),
          ],
        ),
      ),
      if (divider) const Divider(height: 1, color: PetColors.line),
    ],
  );
  Widget text(String value) => Text(value, style: petText(18));
  Future<void> floor(ActivityData p) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('층별 안내', style: petText(24)),
            const SizedBox(height: 16),
            Text(
              p['floor_guide']?.toString().trim().isNotEmpty == true
                  ? p['floor_guide']
                  : '아직 등록된 층별 안내가 없어요. 기관에 정확한 입구와 프로그램실 위치를 확인해 주세요.',
              style: petText(18, weight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            ActivityButton('확인', onTap: () => Navigator.pop(c)),
          ],
        ),
      ),
    ),
  );
  Future<void> externalApplication(ActivityData p) async {
    final phone = '${p['contact_phone'] ?? ''}'.trim();
    if (p['application_method'] == 'phone' && phone.isNotEmpty) {
      await callFacility(context, phone);
      return;
    }
    final map = await activityDialog(
      context,
      title: p['application_method']=='phone'?'전화 신청 안내':'방문 신청 안내',
      message: p['application_method']=='phone'?'연락처가 아직 등록되지 않았어요. 기관 공식 안내에서 접수 연락처를 확인해 주세요.':'아래 내용을 확인하고 기관에서 접수해 주세요. 접수 여부는 기관에서 확인할 수 있어요.',
      action: '위치 확인하기',
      secondary: '닫기',
      icon: Icons.location_on_outlined,
      rows: [
        ('장소', '${p['place_name'] ?? '기관 확인 필요'}'),
        ('대상', '${p['target_audience'] ?? '기관 문의'}'),
        ('준비물', '${p['preparations'] ?? '기관 문의'}'),
        if (phone.isNotEmpty) ('문의', phone),
      ],
    );
    if (map && mounted) {
      await Navigator.push(
        context,
        PageRouteBuilder(
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, a, b) => ActivityMapPage(program: p),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ActivityData>(
    future: future,
    builder: (context, s) {
      final p = s.data?['program'] == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(s.data!['program']);
      final external = ['phone', 'visit'].contains(p['application_method']);
      final isSupport = p['kind'] == 'experience',
          e = s.data?['application'] as Map?;
      final applied =
          e != null &&
          ['applied', 'approved', 'completed'].contains(e['status']);
      final closed =
          p.isNotEmpty &&
          (p['status'] != 'open' ||
              !(DateTime.tryParse('${p['deadline']}')
                      ?.isAfter(DateTime.now()) ??
                  false) ||
              !(DateTime.tryParse('${p['starts_at']}')
                      ?.isAfter(DateTime.now()) ??
                  false));
      final full = (p['enrolled'] as num? ?? 0) >= (p['capacity'] as num? ?? 1);
      final canCancel =
          applied && activityCanCancel(p, Map<String, dynamic>.from(e));
      return PopScope(
        canPop: !busy,
        child: ActivityScreen(
          title: isSupport ? '모집 상세' : '프로그램 상세',
          processing: busy,
          tint: isSupport ? ActivityColors.pink : ActivityColors.sky,
          trailing: Semantics(
            label: favorite ? '관심 프로그램 해제' : '관심 프로그램 저장',
            button: true,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: favorite ? '관심 프로그램 해제' : '관심 프로그램 저장',
                onPressed: p.isEmpty || favoriteBusy ? null : toggleFavorite,
                icon: Icon(
                  favorite ? Icons.favorite : Icons.favorite_border,
                  color: PetColors.pink,
                ),
              ),
            ),
          ),
          bottom: p.isEmpty
              ? null
              : busy
              ? const ActivityButton('처리 중…', onTap: null)
              : external
              ? ActivityButton(
                  closed
                      ? '모집이 마감됐어요'
                      : p['application_method'] == 'phone' &&
                            '${p['contact_phone'] ?? ''}'.trim().isNotEmpty
                      ? '전화로 신청 문의'
                      : p['application_method']=='phone'?'신청 안내 확인':'방문 신청 안내',
                  onTap: closed ? null : () => externalApplication(p),
                )
              : applied
              ? Row(
                  children: [
                    Expanded(
                      child: Text(
                        activityStatuses[e['status']] ?? '',
                        style: petText(17, color: PetColors.secondary),
                      ),
                    ),
                    Expanded(
                      child: ActivityButton(
                        '나의 활동에서 보기',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ActivitySectionPage(
                              section: isSupport
                                  ? ActivitySection.support
                                  : ActivitySection.mine,
                              repository: repo,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : ActivityButton(
                  closed
                      ? '모집이 마감됐어요'
                      : full
                      ? '정원이 모두 찼어요'
                      : isSupport
                      ? '이 모집에 지원하기'
                      : '신청하기',
                  onTap: closed || full
                      ? null
                      : () => isSupport
                            ? support(s.data!)
                            : act(s.data!, cancel: false),
                ),
          child: s.connectionState != ConnectionState.done
              ? const SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: ActivitySkeleton(),
                )
              : s.hasError
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ActivityEmpty(
                      '프로그램을 불러오지 못했어요',
                      message: '인터넷 연결을 확인한 뒤 다시 시도해 주세요.',
                      error: true,
                      action: '다시 시도',
                      onAction: reload,
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      ActivityCard(
                        color: isSupport
                            ? const Color(0xFFCF4C87)
                            : ActivityColors.blue,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                PetPill(
                                  '${p['category']}',
                                  color: Colors.white,
                                  ink: PetColors.secondary,
                                  fontSize: 14,
                                ),
                                PetPill(
                                  applied
                                      ? activityStatuses[e['status']] ?? ''
                                      : closed || full
                                      ? '모집 마감'
                                      : '모집 중',
                                  color: closed || full
                                      ? PetColors.yellow
                                      : PetColors.mint,
                                  ink: closed || full
                                      ? PetColors.orange
                                      : PetColors.green,
                                  fontSize: 14,
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '${p['title']}',
                              style: petText(
                                27,
                                color: Colors.white,
                                weight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${p['org_name']}',
                              style: petText(
                                18,
                                color: const Color(0xFFE2F1FA),
                              ),
                            ),
                            if (p['sponsored'] == true)
                              Text(
                                '기관 후원 · 우선 노출',
                                style: petText(14, color: Colors.white),
                              ),
                          ],
                        ),
                      ),
                      if (external) ...[
                        const ActivityHeading('참여 신청 안내'),
                        ActivityCard(
                          color: const Color(0xFFFFF2DC),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                p['application_method'] == 'phone'
                                    ? '전화로 접수하는 프로그램이에요'
                                    : '기관에 방문해 접수하는 프로그램이에요',
                                style: petText(21),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '참여 조건과 준비물을 확인한 뒤 기관에 신청해 주세요.',
                                style: petText(17, color: PetColors.secondary),
                              ),
                              if ('${p['contact_phone'] ?? ''}'
                                  .trim()
                                  .isNotEmpty)
                                TextButton.icon(
                                  onPressed: () =>
                                      callFacility(context, p['contact_phone']),
                                  icon: const Icon(Icons.phone_outlined),
                                  label: Text('${p['contact_phone']}'),
                                ),
                            ],
                          ),
                        ),
                      ],
                      ActivityHeading(isSupport ? '모집 정보' : '한눈에 보기'),
                      ActivityCard(
                        child: Column(
                          children: [
                            infoRow(
                              Icons.calendar_month_outlined,
                              '일정',
                              text(
                                '${activityDate(p['starts_at'])}\n~ ${activityDate(p['ends_at'])}',
                              ),
                            ),
                            infoRow(
                              Icons.location_on_outlined,
                              '장소',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  text('${p['place_name']}'),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      TextButton.icon(
                                        onPressed:
                                            ActivityMapPage.hasCoordinates(p)
                                            ? () => Navigator.push(
                                                context,
                                                PageRouteBuilder<void>(transitionDuration:Duration.zero,reverseTransitionDuration:Duration.zero,
                                                  pageBuilder: (_,a,b) =>
                                                      ActivityMapPage(
                                                        program: p,
                                                        mapPlaceholder: widget
                                                            .mapPlaceholder,
                                                      ),
                                                ),
                                              )
                                            : null,
                                        icon: const Icon(Icons.map_outlined),
                                        label: const Text('지도 보기'),
                                      ),
                                      TextButton(
                                        onPressed: () => floor(p),
                                        child: const Text('층별 안내'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            infoRow(
                              Icons.people_outline,
                              '대상',
                              text(
                                '${p['target_audience']?.toString().isNotEmpty == true ? p['target_audience'] : '참여 대상은 기관에 확인해 주세요'}',
                              ),
                            ),
                            infoRow(
                              Icons.payments_outlined,
                              '비용',
                              text(
                                applied
                                    ? '확정 참여비 ${activityMoney(e['final_fee'])}'
                                    : '예상 참여비 ${activityMoney(s.data!['quote'])}',
                              ),
                            ),
                            infoRow(
                              Icons.shopping_bag_outlined,
                              '준비물',
                              text(
                                '${p['preparations']?.toString().isNotEmpty == true ? p['preparations'] : '등록된 준비물 안내가 없어요'}',
                              ),
                            ),
                            infoRow(
                              Icons.assignment_outlined,
                              '모집 인원',
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  text(
                                    '${p['enrolled']}/${p['capacity']}명 · ${activityShortDate(p['deadline'])}까지',
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        ((p['enrolled'] as num) /
                                                (p['capacity'] as num))
                                            .clamp(0, 1)
                                            .toDouble(),
                                    minHeight: 7,
                                    color: ActivityColors.blue,
                                    backgroundColor: PetColors.line,
                                  ),
                                ],
                              ),
                              divider: false,
                            ),
                          ],
                        ),
                      ),
                      const ActivityHeading('활동 안내'),
                      ActivityCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${p['description']}',
                              style: petText(17, weight: FontWeight.w500),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              '참여 방식 ${p['participation']} · 난이도 ${p['difficulty']}\n이동수단 ${(p['transports'] as List? ?? []).join(', ')}',
                              style: petText(15, color: PetColors.secondary),
                            ),
                          ],
                        ),
                      ),
                      const ActivityHeading('참여하면 받는 것'),
                      ActivityCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Wrap(
                              spacing: 10,
                              runSpacing: 6,
                              children: [
                                PetPill(
                                  '+ 200 P',
                                  color: PetColors.yellow,
                                  ink: Color(0xFF946100),
                                ),
                                PetPill('+ 50 EXP'),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '기관이 참여를 확인하면 나의 활동에서 받을 수 있어요. 콩이 입양 후 한 번만 지급돼요.',
                              style: petText(16, color: PetColors.secondary),
                            ),
                            if (isSupport) ...[
                              const SizedBox(height: 12),
                              Text(
                                '경험 나눔 완료 시 30일간 유료 기관 프로그램 참여비 50% 혜택도 적용돼요.',
                                style: petText(16, color: PetColors.green),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (applied) ...[
                        const SizedBox(height: 18),
                        ActivityCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${activityStatuses[e['status']]} · 확정 참여비 ${activityMoney(e['final_fee'])}',
                                style: petText(18, color: ActivityColors.blue),
                              ),
                              if (canCancel)
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => act(s.data!, cancel: true),
                                  child: const Text('신청 취소'),
                                ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        '거리는 기준 장소에서의 직선거리예요. 실제 이동 경로와 시간은 달라질 수 있어요. 앱에서는 결제하지 않아요.',
                        textAlign: TextAlign.center,
                        style: petText(14, color: PetColors.secondary),
                      ),
                    ],
                  ),
                ),
        ),
      );
    },
  );
}

class ActivityReceiptPage extends StatelessWidget {
  const ActivityReceiptPage({
    super.key,
    required this.program,
    required this.repository,
    required this.support,
    this.application,
  });
  final ActivityData program;
  final ActivityRepository repository;
  final bool support;
  final dynamic application;
  @override
  Widget build(BuildContext context) => ActivityScreen(
    title: support ? '지원 완료' : '신청 완료',
    tint: support ? ActivityColors.pink : ActivityColors.mint,
    bottom: ActivityButton(
      support ? '지원 현황 보기' : '나의 활동에서 보기',
      onTap: () => Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ActivitySectionPage(
            section: support ? ActivitySection.support : ActivitySection.mine,
            repository: repository,
          ),
        ),
      ),
    ),
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 20),
        const Center(
          child: Icon(
            Icons.check_circle_outline,
            size: 80,
            color: PetColors.green,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          support ? '지원했어요!' : '신청했어요!',
          textAlign: TextAlign.center,
          style: petText(30),
        ),
        const SizedBox(height: 8),
        Text(
          '${program['title']} · ${program['place_name']}',
          textAlign: TextAlign.center,
          style: petText(18, color: PetColors.secondary),
        ),
        const SizedBox(height: 24),
        ActivityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1  ${support ? '지원' : '신청'} 완료', style: petText(20)),
              Text(
                '현재 상태: ${activityStatuses[application?['status']] ?? '승인 대기'}',
                style: petText(16, color: PetColors.secondary),
              ),
              const SizedBox(height: 22),
              Text('2  기관 확인', style: petText(20)),
              Text(
                '기관의 승인 여부를 나의 활동에서 확인해 주세요.',
                style: petText(16, color: PetColors.secondary),
              ),
              const SizedBox(height: 22),
              Text('3  참여 후 보상 받기', style: petText(20)),
              Text(
                '기관의 참여 완료 확인 후 보상을 받을 수 있어요.',
                style: petText(16, color: PetColors.secondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(support ? '모집 상세로 돌아가기' : '프로그램 상세로 돌아가기'),
        ),
      ],
    ),
  );
}

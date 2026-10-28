part of 'activity_hub_page.dart';

class _ActivitySectionPageState extends State<ActivitySectionPage> {
  late final repo = widget.repository ?? ActivityRepository();
  late Future<ActivityData> future = repo.home();
  late final keyword = TextEditingController(text: widget.initialQuery);
  late String? categoryFilter = widget.initialCategory;
  bool busy = false;
  String historyView = '신청 내역', supportView = '진행 중', sort = '가까운 순';
  @override
  void dispose() {
    keyword.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    if (!mounted) return;
    final next = repo.home();
    setState(() {
      future = next;
    });
    try {
      await next;
    } catch (_) {}
  }

  Future<void> open(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) {
      await reload();
      if (mounted) await ActivityPetScope.maybeOf(context)?.load();
    }
  }

  void section(ActivitySection value) =>
      open(ActivitySectionPage(section: value, repository: repo));
  void detail(ActivityData p) =>
      open(ActivityDetailPage(programId: p['id'], repository: repo));
  Future<void> plan({bool rebuild = false}) async {
    if (busy) return;
    if (rebuild &&
        !await activityDialog(
          context,
          title: '미션을 다시 고를까요?',
          message: '아직 신청하지 않은 미션만 다시 골라요. 신청·참여 이력은 유지돼요.',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await repo.plan(rebuild: rebuild);
      await reload();
    } catch (_) {
      if (mounted) await activityFailure(context, title: '미션을 만들지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget program(ActivityData p, {String? label, bool recommended = false}) =>
      ActivityListingCard(
        program: p,
        label: label,
        recommended: recommended,
        onTap: () => detail(p),
      );
  void settings(ActivityData d) => open(
    ActivityPreferencesPage(initial: d['preferences'], repository: repo),
  );
  List<Widget> find(ActivityData d) {
    final pref = d['preferences'] as Map?,
        rows = filter(activityRows(d['recommendations']));
    return [
      if (pref == null)
        ActivityEmpty(
          '아직 추천 조건이 없어요',
          message: '기준 장소와 관심 분야를 정하면\n편한 활동을 찾아드려요',
          icon: Icons.tune,
          action: '추천 조건 설정하기',
          onAction: () => settings(d),
        )
      else ...[
        ActivityCard(
          onTap: () => settings(d),
          child: Row(
            children: [
              const Icon(Icons.tune, color: ActivityColors.blue, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('내 추천 조건', style: petText(20)),
                    Text(
                      activityPreferenceSummary(
                        Map<String, dynamic>.from(pref),
                      ),
                      style: petText(16, color: PetColors.secondary),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => settings(d),
                child: const Text('바꾸기'),
              ),
            ],
          ),
        ),
        if (rows.isEmpty) ...[
          const SizedBox(height: 16),
          ActivityEmpty(
            '조건에 맞는 활동이 아직 없어요',
            message: '이동 거리나 관심 분야를\n조금 바꿔서 찾아보세요',
            action: '추천 조건 바꾸기',
            onAction: () => settings(d),
            secondary: '전체 프로그램 탐색',
            onSecondary: () => section(ActivitySection.programs),
          ),
        ] else ...[
          ActivityHeading(
            '조건에 맞는 활동 ${rows.length}개',
            trailing: Text(
              '가까운 순',
              style: petText(15, color: PetColors.secondary),
            ),
          ),
          for (final p in rows) program(p, recommended: true),
        ],
      ],
      const SizedBox(height: 18),
      if (pref == null || rows.isNotEmpty)
        ActivityButton(
          '전체 프로그램 탐색',
          icon: Icons.search,
          onTap: () => section(ActivitySection.programs),
          light: true,
        ),
      const SizedBox(height: 12),
      Text(
        '거리는 기준 장소에서의 직선거리예요. 실제 이동 경로와 시간은 달라질 수 있어요.',
        textAlign: TextAlign.center,
        style: petText(14, color: PetColors.secondary),
      ),
    ];
  }

  Future<void> replace(ActivityData mission) async {
    if (busy) return;
    final stage = (mission['stage'] as num).toInt();
    setState(() => busy = true);
    try {
      final choices = await repo.missionChoices(stage);
      if (!mounted) return;
      String? chosen;
      final selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        builder: (c) => StatefulBuilder(
          builder: (c, change) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(c).height * .72,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('$stage단계 프로그램 바꾸기', style: petText(23)),
                    const SizedBox(height: 12),
                    Text(
                      '신청 전 미션만 바꿀 수 있어요. 기존 신청·참여 기록은 유지돼요.',
                      style: petText(16, color: PetColors.secondary),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          if (choices.isEmpty)
                            const Text('조건에 맞는 다른 프로그램이 없어요.'),
                          for (final p in choices)
                            ListTile(
                              leading: Icon(
                                chosen == p['id']
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: ActivityColors.blue,
                              ),
                              onTap: () => change(() => chosen = p['id']),
                              title: Text(p['title']),
                              subtitle: Text(
                                '${p['place_name']} · ${activityShortDate(p['starts_at'])}',
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ActivityButton(
                      '이 프로그램으로 바꾸기',
                      onTap: chosen == null
                          ? null
                          : () => Navigator.pop(c, chosen),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (selected != null) {
        await repo.replaceMission(stage, selected);
        await reload();
      }
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '다른 미션을 불러오지 못했어요',
          message: '인터넷 연결과 활동 서버 설정을 확인한 뒤 다시 시도해 주세요. 기존 미션은 유지돼요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Widget> missions(ActivityData d) {
    final rows = activityRows(d['missions']),
        completed = rows.where((m) => m['status'] == 'completed').length;
    if (d['preferences'] == null) {
      return [
        Text(
          '내 조건에 맞는 프로그램을 골라 이번 주 미션으로 만들어 드려요',
          style: petText(16, color: PetColors.secondary),
        ),
        const SizedBox(height: 18),
        ActivityEmpty(
          '추천 조건을 먼저 정해 주세요',
          message: '기준 장소와 관심 분야를 정하면\n이번 주 미션을 만들어요',
          icon: Icons.flag_outlined,
          action: '추천 조건 설정하기',
          onAction: () => settings(d),
        ),
        const ActivityHeading('이렇게 진행돼요'),
        ActivityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('1  프로그램 3개 추천', style: petText(18)),
              const SizedBox(height: 16),
              Text('2  신청하고 참여', style: petText(18)),
              const SizedBox(height: 16),
              Text('3  기관 확인 후 보상', style: petText(18)),
            ],
          ),
        ),
      ];
    }
    return [
      ActivityCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '이번 주 미션 $completed/${rows.length}개 완료',
                  style: petText(20),
                ),
                TextButton(
                  onPressed: () => settings(d),
                  child: const Text('조건 바꾸기 ›'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: rows.isEmpty ? 0 : completed / rows.length,
                minHeight: 10,
                color: ActivityColors.blue,
                backgroundColor: PetColors.line,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              activityPreferenceSummary(
                Map<String, dynamic>.from(d['preferences']),
              ),
              style: petText(16, color: PetColors.secondary),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (rows.isEmpty)
        ActivityEmpty(
          '이번 주 미션을 골라 볼까요?',
          message: '조건에 맞는 실제 프로그램이 있어야 미션이 만들어져요.',
          icon: Icons.flag_outlined,
          action: busy ? '미션 준비 중…' : '이번 주 미션 만들기',
          onAction: busy ? null : () => plan(),
        ),
      if (rows.isNotEmpty && completed == rows.length)
        ActivityCard(
          color: PetColors.mint,
          child: Column(
            children: [
              Text('이번 주 미션을 모두 마쳤어요!', style: petText(22)),
              const SizedBox(height: 8),
              Text(
                '단계별 미션 보상을 확인해 주세요. 다음 주 월요일에 새 미션을 만들 수 있어요.',
                style: petText(16, color: PetColors.secondary),
              ),
              const SizedBox(height: 14),
              ActivityButton(
                '콩이 보러 가기',
                color: PetColors.purple,
                onTap: ActivityPetScope.openPetOf(context),
              ),
            ],
          ),
        ),
      for (final m in rows) ...[const SizedBox(height: 14), _missionCard(m, d)],
      if (rows.isNotEmpty)
        TextButton(
          onPressed: busy ? null : () => plan(rebuild: true),
          child: const Text('신청 전 미션 다시 고르기'),
        ),
      const SizedBox(height: 12),
      Text(
        '프로그램별 미션 보상은 단계마다 주 1회 받을 수 있어요. 기관이 참여를 확인한 뒤 지급돼요.',
        style: petText(14, color: PetColors.secondary),
      ),
    ];
  }

  Future<void> claimMission(int stage) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await repo.claimProgramMission(stage);
      await reload();
      if (!mounted) return;
      await ActivityPetScope.maybeOf(context)?.load();
      if (!mounted) return;
      await AttendanceScope.maybeOf(context)?.refresh();
      if (!mounted) return;
      await activityDialog(
        context,
        title: result['already'] == true ? '이미 받은 보상이에요' : '$stage단계 보상을 받았어요!',
        message: '기관에서 참여를 확인한 미션의 보상이에요.',
        icon: Icons.card_giftcard_outlined,
        color: PetColors.purple,
        rows: [
          ('포인트', '+${result['points']} P'),
          ('성장 경험치', '+${result['experience']} EXP'),
        ],
        secondary: '닫기',
      );
    } catch (_) {
      if (mounted) {
        await activityFailure(
          context,
          title: '미션 보상을 확인해 주세요',
          message: '콩이 입양과 기관의 참여 완료 확인이 필요해요. 인터넷 연결과 미션 보상 서버 설정도 확인해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool missionClaimed(ActivityData m, ActivityData d) {
    final week = '${m['week_start'] ?? ''}'.split('T').first;
    return activityRows(d['mission_rewards'])
        .any((r) => r['reference'] == 'program-mission:$week:${m['stage']}');
  }

  Widget _missionCard(ActivityData m, ActivityData d) {
    final p = Map<String, dynamic>.from(m['program']);
    final done = m['status'] == 'completed',
        active = ['applied', 'approved'].contains(m['status']);
    final claimed = missionClaimed(m, d), stage = (m['stage'] as num).toInt();
    final e = activityRows(d['applications'])
        .where(
          (e) => e['program_id'] == p['id'] || e['program']?['id'] == p['id'],
        )
        .firstOrNull;
    return ActivityCard(
      color: done ? PetColors.mint : Colors.white,
      border: active
          ? const BorderSide(color: ActivityColors.blue, width: 2)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                '${m['stage']}단계 · ${['익숙한 동네', '새로운 장소', '함께하는 활동'][((m['stage'] as num).toInt() - 1).clamp(0, 2)]}',
                style: petText(16, color: ActivityColors.blue),
              ),
              PetPill(
                activityStatuses[m['status']] ?? '아직 신청 전',
                color: done
                    ? PetColors.mint
                    : active
                    ? PetColors.yellow
                    : const Color(0xFFEDF2F7),
                ink: done
                    ? PetColors.green
                    : active
                    ? PetColors.orange
                    : PetColors.secondary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(p['title'], style: petText(23)),
          Text(
            p['org_name'] ?? p['place_name'] ?? '',
            style: petText(17, color: PetColors.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            activityShortDate(p['starts_at']),
            style: petText(16, color: PetColors.secondary),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: PetPill(
              stage == 3 ? '+ 30 EXP' : '+ ${stage == 1 ? 50 : 100} P',
              color: stage == 3 ? PetColors.lavender : PetColors.yellow,
              ink: stage == 3 ? PetColors.purple : PetColors.orange,
            ),
          ),
          if (done && claimed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '✓ 미션 보상 지급 완료',
                style: petText(17, color: PetColors.green),
              ),
            ),
          if (done && !claimed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ActivityButton(
                '미션 보상 받기',
                onTap: busy ? null : () => claimMission(stage),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (!done && !active)
                ActivityButton(
                  '바꾸기',
                  onTap: busy ? null : () => replace(m),
                  light: true,
                  icon: Icons.swap_horiz,
                ),
              if (e != null && activityCanCancel(p, e))
                ActivityButton(
                  '신청 취소',
                  onTap: busy ? null : () => cancel(e),
                  light: true,
                ),
              ActivityButton(
                done
                    ? '참여 기록 보기'
                    : active
                    ? '상세 보기'
                    : '신청하기',
                onTap: () => detail(p),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> experiences(ActivityData d) {
    final rows = activityRows(d['experiences']);
    return [
      ActivityButton(
        '나눌 경험 등록',
        icon: Icons.add,
        onTap: () => open(ActivityExperiencePage(repository: repo)),
      ),
      const SizedBox(height: 12),
      const ActivityPrivacyNotice(),
      if (rows.isEmpty) ...[
        const SizedBox(height: 18),
        ActivityEmpty(
          '아직 등록한 경험이 없어요.',
          message: '요리, 악기, 텃밭, 스마트폰…\n작은 경험도 이웃에게 큰 도움이 돼요',
          icon: Icons.favorite_border,
          action: '나눌 경험 등록',
          onAction: () => open(ActivityExperiencePage(repository: repo)),
        ),
      ] else ...[
        ActivityHeading('등록한 경험 ${rows.length}개', color: PetColors.pink),
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ActivityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      PetPill(e['category'], fontSize: 14),
                      PetPill(
                        e['active'] == true ? '참여 가능' : '쉬는 중',
                        color: e['active'] == true
                            ? PetColors.mint
                            : const Color(0xFFEDF2F7),
                        ink: e['active'] == true
                            ? PetColors.green
                            : PetColors.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(e['title'], style: petText(21)),
                  Text(
                    '${e['available_time']} · ${e['activity_type']}',
                    style: petText(16, color: PetColors.secondary),
                  ),
                  Text(
                    e['preferred_place'] ?? '',
                    style: petText(16, color: PetColors.secondary),
                  ),
                  TextButton.icon(
                    onPressed: () => open(
                      ActivityExperiencePage(existing: e, repository: repo),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('수정'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('경험 나눔 참여 가능', style: petText(16)),
                    value: e['active'] == true,
                    onChanged: busy ? null : (v) => toggleExperience(e, v),
                  ),
                ],
              ),
            ),
          ),
      ],
    ];
  }

  Future<void> toggleExperience(ActivityData e, bool value) async {
    setState(() => busy = true);
    try {
      await repo.experience({'active': value}, id: e['id']);
      await reload();
    } catch (_) {
      if (mounted) await activityFailure(context, title: '참여 상태를 바꾸지 못했어요');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> cancel(ActivityData e) async {
    if (busy ||
        !await activityDialog(
          context,
          title: '신청을 취소할까요?',
          message: '취소하면 자리가 다른 분께 넘어가요. 다시 신청할 때 자리가 없을 수 있어요.',
          action: '신청 취소하기',
          secondary: '그대로 두기',
          color: PetColors.orange,
          icon: Icons.error_outline,
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await repo.cancel(e['id']);
      await reload();
      if (mounted) {
        await activityDialog(
          context,
          title: '신청을 취소했어요',
          message: '언제든 다시 신청할 수 있어요.',
          icon: Icons.check,
          secondary: '닫기',
        );
      }
    } catch (_) {
      if (mounted) await activityFailure(context, title: '취소 상태를 확인해 주세요');
      await reload();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> claimProgram(String id) async {
    final pet = ActivityPetScope.maybeOf(context);
    if (pet == null || !pet.adopted) {
      await activityDialog(
        context,
        title: '콩이를 먼저 만나 주세요',
        message: '홈에서 반려동물을 입양한 뒤 참여 보상을 받을 수 있어요.',
        secondary: '닫기',
      );
      return;
    }
    try {
      final outcome = await pet.run('program_reward', {'id': id});
      if (!mounted) return;
      await AttendanceScope.maybeOf(context)?.refresh();
      if (!mounted) return;
      await activityDialog(
        context,
        title: outcome.already ? '이미 받은 보상이에요' : '참여 보상을 받았어요!',
        message: '기관에서 확인한 참여 기록으로 지급해요.',
        icon: Icons.card_giftcard_outlined,
        rows: [
          ('포인트', '+${outcome.points} P'),
          ('성장 경험치', '+${outcome.experience} EXP'),
        ],
        secondary: '닫기',
      );
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) await activityFailure(context, title: '보상을 받지 못했어요');
    }
  }

  List<Widget> applications(ActivityData d, {bool supportOnly = false}) {
    final all = activityRows(d['applications'])
        .where((e) => !supportOnly || e['program']['kind'] == 'experience')
        .toList();
    final rows = all
        .where(
          (e) => supportOnly
              ? supportView == '전체' ||
                    (supportView == '완료'
                        ? e['status'] == 'completed'
                        : ['applied', 'approved'].contains(e['status']))
              : historyView == '참여 이력'
              ? e['status'] == 'completed'
              : e['status'] != 'completed',
        )
        .toList();
    return [
      _tabs(
        supportOnly ? ['진행 중', '완료', '전체'] : ['신청 내역', '참여 이력', '혜택'],
        supportOnly ? supportView : historyView,
        (v) => setState(() {
          if (supportOnly) {
            supportView = v;
          } else {
            historyView = v;
          }
        }),
      ),
      const SizedBox(height: 18),
      if (!supportOnly && historyView == '혜택')
        ...benefits(d)
      else if (rows.isEmpty)
        ActivityEmpty(
          supportOnly
              ? '아직 지원한 경험 나눔이 없어요.'
              : historyView == '참여 이력'
              ? '아직 완료한 활동이 없어요.'
              : '아직 신청한 활동이 없어요.',
          message: supportOnly
              ? '내 경험을 기다리는 기관을 찾아보세요'
              : '마음에 드는 프로그램을 신청하면\n여기에서 진행 상태를 볼 수 있어요',
          icon: Icons.event_available_outlined,
          action: supportOnly ? '기관 모집 탐색' : '맞춤 활동 찾기',
          onAction: () => section(
            supportOnly ? ActivitySection.recruitment : ActivitySection.find,
          ),
          secondary: supportOnly ? null : '전체 프로그램 보기',
          onSecondary: () => section(ActivitySection.programs),
        )
      else ...[
        if (!supportOnly && historyView == '참여 이력')
          ActivityCard(
            child: Wrap(
              spacing: 18,
              runSpacing: 12,
              children: [
                Text('${rows.length}회\n참여 완료', style: petText(20)),
                Text(
                  '보상은 기관 참여 확인 후\n한 번만 받을 수 있어요',
                  style: petText(16, color: PetColors.secondary),
                ),
              ],
            ),
          ),
        for (final group
            in (supportOnly || historyView == '신청 내역'
                ? ['진행 중', '지난 신청']
                : ['참여 기록'])) ...[
          if (rows.any(
            (e) =>
                group == '참여 기록' ||
                (group == '진행 중') ==
                    ['applied', 'approved'].contains(e['status']),
          )) ...[
            ActivityHeading(group, color: PetColors.green),
            ActivityCard(
              child: Column(
                children: [
                  for (final e in rows.where(
                    (e) =>
                        group == '참여 기록' ||
                        (group == '진행 중') ==
                            ['applied', 'approved'].contains(e['status']),
                  ))
                    _applicationRow(e),
                ],
              ),
            ),
          ],
        ],
      ],
    ];
  }

  Widget _applicationRow(ActivityData e) {
    final p = Map<String, dynamic>.from(e['program']),
        date = DateTime.tryParse('${e['program']['starts_at']}')?.toLocal();
    final pet = ActivityPetScope.maybeOf(context);
    final rewarded =
        pet?.programs.any((p) => p['id'] == e['id'] && p['rewarded'] == true) ??
        false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE1F0FC),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Text(
                  date == null ? '' : '${date.month}월',
                  style: petText(14, color: ActivityColors.muted),
                ),
                Text(
                  date == null ? '–' : '${date.day}',
                  style: petText(26, color: ActivityColors.blue),
                ),
                if (date != null)
                  Text(
                    ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1],
                    style: petText(14, color: ActivityColors.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(p['title'], style: petText(20)),
                const SizedBox(height: 5),
                Text(
                  '${p['org_name'] ?? p['place_name']} · ${activityShortDate(p['starts_at'])}',
                  style: petText(15, color: PetColors.secondary),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PetPill(
                    activityStatuses[e['status']] ?? '${e['status']}',
                    color: e['status'] == 'rejected'
                        ? const Color(0xFFFFECEC)
                        : e['status'] == 'applied'
                        ? PetColors.yellow
                        : PetColors.mint,
                    ink: e['status'] == 'rejected'
                        ? Colors.redAccent
                        : e['status'] == 'applied'
                        ? PetColors.orange
                        : PetColors.green,
                    fontSize: 14,
                  ),
                ),
                if (e['rejection_reason'] != null)
                  Text(
                    '${e['rejection_reason']}',
                    style: petText(15, color: Colors.redAccent),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (activityCanCancel(p, e))
                      TextButton(
                        onPressed: busy ? null : () => cancel(e),
                        child: const Text('신청 취소'),
                      ),
                    TextButton(
                      onPressed: () => detail(p),
                      child: const Text('상세 보기'),
                    ),
                    if (e['experience_snapshot'] != null)
                      TextButton(
                        onPressed: () => submitted(e),
                        child: const Text('제출 내용 보기'),
                      ),
                    if (e['status'] == 'completed' && !rewarded)
                      TextButton(
                        onPressed: pet?.busy == true
                            ? null
                            : () => claimProgram(e['id']),
                        child: const Text('참여 보상 받기'),
                      ),
                    if (rewarded)
                      const PetPill(
                        '✓ 보상 지급 완료',
                        color: PetColors.yellow,
                        ink: PetColors.orange,
                        fontSize: 13,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> submitted(ActivityData e) => showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('제출한 경험', style: petText(23)),
            const SizedBox(height: 14),
            Text('${e['experience_snapshot']['title']}', style: petText(20)),
            Text(
              '${e['experience_snapshot']['description']}',
              style: petText(17, weight: FontWeight.w500),
            ),
            const SizedBox(height: 14),
            Text(
              '기관에 하고 싶은 말\n${e['application_note'] ?? '추가로 남긴 말이 없어요'}',
              style: petText(16, color: PetColors.secondary),
            ),
            const SizedBox(height: 18),
            ActivityButton('닫기', onTap: () => Navigator.pop(c)),
          ],
        ),
      ),
    ),
  );
  List<Widget> benefits(ActivityData d) {
    final expiry = DateTime.tryParse('${d['benefit_expires_at']}');
    final active = expiry?.isAfter(DateTime.now()) ?? false;
    final expired = activityRows(d['benefits'])
        .where(
          (b) =>
              DateTime.tryParse('${b['expires_at']}')
                  ?.isBefore(DateTime.now()) ??
              false,
        )
        .toList();
    return [
      ActivityCard(
        color: const Color(0xFFE2F1FC),
        child: Text(
          '프로그램마다 무료인 경우에는 기본 혜택이 달라요. 함께 적용할 수 없는 혜택은 중복되지 않아요.',
          style: petText(15, color: ActivityColors.blue),
        ),
      ),
      const SizedBox(height: 18),
      if (active) ...[
        const ActivityHeading('쓸 수 있는 혜택', color: PetColors.green),
        ActivityCard(
          child: Row(
            children: [
              const Icon(
                Icons.local_offer_outlined,
                color: PetColors.green,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PetPill(
                      expiry!.difference(DateTime.now()).inDays <= 3
                          ? '만료 임박'
                          : '적용 중',
                      color: PetColors.mint,
                      ink: PetColors.green,
                    ),
                    const SizedBox(height: 10),
                    Text('유료 기관 프로그램 참여비 50% 혜택', style: petText(21)),
                    Text(
                      '${activityDate(d['benefit_expires_at'])}까지 새 신청에 적용돼요. 중복 합산되지 않아요.',
                      style: petText(16, color: PetColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ] else
        ActivityEmpty(
          '현재 적용 중인 혜택이 없어요.',
          message: '경험 나눔을 완료하고 기관이 확인하면\n30일간 참여비 50% 혜택을 받아요',
          icon: Icons.local_offer_outlined,
          action: '기관 모집 탐색',
          onAction: () => section(ActivitySection.recruitment),
        ),
      if (expired.isNotEmpty) ...[
        const ActivityHeading('지난 혜택', color: ActivityColors.muted),
        for (final benefit in expired)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ActivityCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PetPill(
                    '만료',
                    color: Color(0xFFEDF2F7),
                    ink: PetColors.secondary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '참여비 50% 혜택',
                    style: petText(20, color: PetColors.secondary),
                  ),
                  Text(
                    '${activityDate(benefit['expires_at'])} 종료',
                    style: petText(16, color: PetColors.secondary),
                  ),
                ],
              ),
            ),
          ),
      ],
      if (d['benefits_unavailable'] == true)
        Text(
          '지난 혜택 내역을 불러오지 못했어요. 아래로 당겨 다시 확인해 주세요.',
          style: petText(15, color: PetColors.secondary),
        ),
    ];
  }

  Widget _tabs(
    List<String> values,
    String selected,
    ValueChanged<String> changed,
  ) => ActivityCard(
    padding: 5,
    color: const Color(0xFFF8FCFA),
    child: Row(
      children: [
        for (final value in values)
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: value == selected
                    ? ActivityColors.blue
                    : Colors.transparent,
                foregroundColor: value == selected
                    ? Colors.white
                    : PetColors.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () => changed(value),
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    ),
  );
  List<Widget> experienceHub(ActivityData d) => [
    Text(
      '쌓아 온 경험을 동네 기관과 이웃에게 나눠요',
      style: petText(16, color: PetColors.secondary),
    ),
    const SizedBox(height: 16),
    ActivityCard(
      color: PetColors.pinkTint,
      child: Text(
        '나눌 경험 ${activityRows(d['experiences']).length}개 · 지원 ${activityRows(d['applications']).where((e) => e['program']?['kind'] == 'experience').length}건',
        style: petText(18),
      ),
    ),
    const ActivityHeading('무엇을 할까요?', color: PetColors.pink),
    for (final e in [
      (
        ActivitySection.myExperiences,
        Icons.edit_outlined,
        '내 경험 관리',
        '내 경험 등록·수정, 참여 가능 상태',
      ),
      (
        ActivitySection.recruitment,
        Icons.search,
        '기관 모집 탐색',
        '기관이 찾는 경험·도움 살펴보기',
      ),
      (
        ActivitySection.support,
        Icons.assignment_outlined,
        '지원 현황',
        '내 지원과 승인·완료 상태',
      ),
    ]) ...[
      ActivityCard(
        onTap: () => section(e.$1),
        child: Row(
          children: [
            Icon(e.$2, color: ActivityColors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.$3, style: petText(20)),
                  Text(e.$4, style: petText(15, color: PetColors.secondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: ActivityColors.muted),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ],
  ];
  List<Widget> listing(ActivityData d) {
    final rows = matchingPrograms(d), q = keyword.text.trim();
    return [
      TextField(
        controller: keyword,
        onChanged: (_) => setState(() {}),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: '프로그램 검색',
          hintText: '프로그램 이름으로 검색',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: q.isEmpty
              ? null
              : IconButton(
                  tooltip: '검색 지우기',
                  onPressed: () => setState(keyword.clear),
                  icon: const Icon(Icons.close),
                ),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final category in ['전체', ...activityCategories])
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(category),
                  labelStyle: petText(
                    14,
                    color: (categoryFilter ?? '전체') == category
                        ? Colors.white
                        : PetColors.secondary,
                  ),
                  showCheckmark: false,
                  selectedColor: ActivityColors.blue,
                  backgroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  selected: (categoryFilter ?? '전체') == category,
                  onSelected: (_) => setState(
                    () => categoryFilter = category == '전체' ? null : category,
                  ),
                ),
              ),
          ],
        ),
      ),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '모집 중 ${rows.length}개',
            style: petText(16, color: PetColors.secondary),
          ),
          DropdownButton<String>(
            value: sort,
            underline: const SizedBox(),
            items: [
              for (final v in ['가까운 순', '시작일 순', '마감일 순'])
                DropdownMenuItem(
                  value: v,
                  child: Text(
                    v,
                    style: petText(15, color: PetColors.secondary),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => sort = v!),
          ),
        ],
      ),
      if (widget.place != null)
        Text(
          '${widget.place!.name}에서 모집 중인 프로그램이에요.',
          style: petText(16, color: PetColors.secondary),
        ),
      if (rows.isEmpty)
        ActivityEmpty(
          q.isEmpty ? '현재 모집 중인 프로그램이 없어요.' : '“$q” 프로그램이 지금은 없어요',
          message: q.isEmpty
              ? '다른 분야도 살펴보거나\n나중에 다시 확인해 주세요'
              : '다른 이름으로 찾아보거나\n분야를 바꿔서 확인해 보세요',
          action: '분야 전체 보기',
          onAction: () => setState(() {
            categoryFilter = null;
            keyword.clear();
          }),
          secondary: widget.section == ActivitySection.recruitment
              ? '내 경험 보기'
              : '추천 조건 설정',
          onSecondary: () => widget.section == ActivitySection.recruitment
              ? section(ActivitySection.myExperiences)
              : settings(d),
        ),
      for (final p in rows) program(p),
      if (q.isNotEmpty &&
          rows.isEmpty &&
          activityRows(d['programs']).isNotEmpty) ...[
        const ActivityHeading('이런 활동은 어때요?'),
        for (final p
            in activityRows(d['programs'])
                .where(
                  (p) =>
                      p['kind'] ==
                      (widget.section == ActivitySection.recruitment
                          ? 'experience'
                          : 'activity'),
                )
                .take(2))
          program(p),
      ],
      const SizedBox(height: 10),
      Text(
        '표시 거리는 기준 장소에서의 직선거리예요.',
        textAlign: TextAlign.center,
        style: petText(14, color: PetColors.secondary),
      ),
    ];
  }

  List<Widget> content(ActivityData d) => switch (widget.section) {
    ActivitySection.find => find(d),
    ActivitySection.missions => missions(d),
    ActivitySection.mine => applications(d),
    ActivitySection.support => applications(d, supportOnly: true),
    ActivitySection.myExperiences => experiences(d),
    ActivitySection.experience => experienceHub(d),
    ActivitySection.programs || ActivitySection.recruitment => listing(d),
  };
  List<ActivityData> filter(List<ActivityData> rows) {
    final q = keyword.text.trim().toLowerCase();
    final list = rows
        .where(
          (p) =>
              (categoryFilter == null || p['category'] == categoryFilter) &&
              (q.isEmpty ||
                  [
                    'title',
                    'description',
                    'org_name',
                    'place_name',
                    'category',
                  ].any((key) => '${p[key] ?? ''}'.toLowerCase().contains(q))),
        )
        .toList();
    list.sort((a, b) {
      if (sort == '가까운 순') {
        return (a['distance_km'] as num? ?? double.infinity).compareTo(
          b['distance_km'] as num? ?? double.infinity,
        );
      }
      final field = sort == '마감일 순' ? 'deadline' : 'starts_at';
      return '${a[field]}'.compareTo('${b[field]}');
    });
    return list;
  }

  List<ActivityData> matchingPrograms(ActivityData d) =>
      filter(activityRows(d['programs'])).where((p) {
        final place = widget.place;
        if (place != null) {
          final lat = p['lat'], lng = p['lng'];
          return p['place_name']?.toString().trim() == place.name.trim() &&
              lat is num &&
              lng is num &&
              Geolocator.distanceBetween(
                    place.lat,
                    place.lng,
                    lat.toDouble(),
                    lng.toDouble(),
                  ) <=
                  100;
        }
        return p['kind'] ==
            (widget.section == ActivitySection.programs
                ? 'activity'
                : 'experience');
      }).toList();
  Color get tint => switch (widget.section) {
    ActivitySection.mine => ActivityColors.mint,
    ActivitySection.experience ||
    ActivitySection.myExperiences ||
    ActivitySection.recruitment ||
    ActivitySection.support => ActivityColors.pink,
    ActivitySection.missions => ActivityColors.orange,
    _ => ActivityColors.sky,
  };
  @override
  Widget build(BuildContext context) => ActivityScreen(
    title: widget.place == null
        ? activitySectionTitle(widget.section)
        : '앱으로 신청하는 활동',
    tint: tint,
    child: FutureBuilder<ActivityData>(
      future: future,
      builder: (context, snapshot) => RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          physics: const AlwaysScrollableScrollPhysics(),
          children: snapshot.connectionState != ConnectionState.done
              ? [const ActivitySkeleton()]
              : snapshot.hasError
              ? [
                  ActivityEmpty(
                    '활동 정보를 불러오지 못했어요.',
                    message: '인터넷 연결을 확인한 뒤\n다시 시도해 주세요',
                    error: true,
                    icon: Icons.wifi_off_rounded,
                    action: '다시 시도',
                    onAction: reload,
                  ),
                ]
              : content(snapshot.data!),
        ),
      ),
    ),
  );
}

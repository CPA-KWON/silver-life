import 'package:flutter/material.dart';

import '../activity/activity_hub_page.dart';
import '../activity/activity_detail_page.dart';
import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_care_pages.dart';
import 'pet_ads_service.dart';

class PetTodayPage extends StatefulWidget {
  const PetTodayPage({
    super.key,
    required this.pet,
    this.missionsOnly = false,
    this.onOpenProgramMissions,
    this.onOpenPet,
  });
  final PetPreviewController pet;
  final bool missionsOnly;
  final VoidCallback? onOpenProgramMissions, onOpenPet;
  @override
  State<PetTodayPage> createState() => _TodayState();
}

class _TodayState extends State<PetTodayPage> {
  bool adLoading = false;
  Future<void> reward(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    final pet = widget.pet;
    try {
      final result = await pet.run(action, payload);
      if (!mounted) return;
      if (result.already) {
        await petDialog(
          context,
          title: '이미 받은 보상이에요',
          message: '같은 활동의 보상은 한 번만 받아요.',
          emblem: const Icon(
            Icons.check_circle_outline,
            color: PetColors.green,
            size: 40,
          ),
        );
        return;
      }
      final home = await petDialog(
        context,
        title: '보상을 받았어요!',
        message: action == 'program_reward'
            ? '기관에서 참여를 확인했어요.'
            : '오늘도 함께해 주셔서 고마워요.',
        color: PetColors.purple,
        emblem: const Icon(
          Icons.card_giftcard_outlined,
          color: PetColors.purple,
          size: 42,
        ),
        rows: [
          ('받은 포인트', '+ ${result.points} P'),
          ('성장 경험치', '+ ${result.experience} EXP'),
          ('지금 포인트', '${petNumber(pet.points)}P'),
        ],
        action: '콩이에게 돌아가기',
        secondary: '다른 활동 보기',
      );
      if (home && mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  Future<void> ad() async {
    if (adLoading) return;
    setState(() => adLoading = true);
    try {
      if (widget.pet.isPreview) {
        if (!await petDialog(
          context,
          title: '광고 보상 미리보기',
          message: '실제 광고와 포인트가 아닌 디자인 예시예요.',
          action: '완료 예시 보기',
          secondary: '취소',
        )) {
          return;
        }
        await reward('ad_claim');
      } else {
        final result = widget.pet.pendingAd != null
            ? await widget.pet.run('ad_claim', {
                'session': widget.pet.pendingAd,
              })
            : await PetAdsService.watch(widget.pet);
        if (!mounted) return;
        await petDialog(
          context,
          title: '보상을 받았어요!',
          emblem: const Icon(
            Icons.card_giftcard_outlined,
            size: 40,
            color: PetColors.purple,
          ),
          rows: [
            ('광고 보상', '+${result.points}P'),
            ('지금 포인트', '${petNumber(widget.pet.points)}P'),
          ],
        );
      }
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    } finally {
      if (mounted) setState(() => adLoading = false);
    }
  }

  Future<void> programs() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            const ActivitySectionPage(section: ActivitySection.programs),
      ),
    );
    await widget.pet.load();
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: widget.pet,
    builder: (c, _) {
      final pet = widget.pet;
      return PetScreen(
        colors: const [PetColors.background, PetColors.background],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetHeader(widget.missionsOnly ? '주간 미션' : '오늘의 활동', pet: pet),
            if (widget.missionsOnly && !pet.ready) ...[
              PetCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      pet.error == null
                          ? '미션 정보를 확인하고 있어요'
                          : '미션 정보를 불러오지 못했어요',
                      style: petText(20),
                    ),
                    const SizedBox(height: 12),
                    PetPrimary(
                      pet.busy ? '확인 중' : '다시 확인하기',
                      onTap: pet.busy ? null : pet.load,
                    ),
                  ],
                ),
              ),
            ],
            if (widget.missionsOnly && pet.ready && !pet.adopted) ...[
              PetCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('콩이를 입양하면 미션 보상을 받을 수 있어요', style: petText(20)),
                    const SizedBox(height: 12),
                    PetPrimary('반려동물 만나기', onTap: widget.onOpenPet),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!widget.missionsOnly || pet.ready && pet.adopted)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDFF0FB), Color(0xFFF0ECFF)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: PetPhoto(pet: pet, height: 86, mood: 'happy'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${pet.name}에게 줄 보상을 모아요', style: petText(19)),
                          Text(
                            '오늘 받은 보상',
                            style: petText(16, color: PetColors.secondary),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 5,
                            children: [
                              PetPill(
                                '+ ${pet.todayPoints} P',
                                color: PetColors.yellow,
                                ink: const Color(0xFF946100),
                              ),
                              PetPill('+ ${pet.todayExperience} EXP'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (!widget.missionsOnly || pet.ready) ...[
              const SizedBox(height: 24),
              _section('출석 · 주간 미션'),
              PetCard(
                padding: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _badge(
                          Icons.check_box_outlined,
                          PetColors.mint,
                          PetColors.green,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('오늘 출석', style: petText(20)),
                              Text(
                                pet.attendanceRewarded
                                    ? '출석 완료 · 보상을 받았어요'
                                    : pet.attended
                                    ? '출석 완료 · 성장 경험치를 받아주세요'
                                    : '오늘도 출석하고 함께 자라요',
                                style: petText(15, color: PetColors.secondary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed:
                              !pet.adopted || pet.attendanceRewarded || pet.busy
                              ? null
                              : () => reward('attendance'),
                          child: Text(
                            pet.attendanceRewarded
                                ? '✓ 받음'
                                : pet.attended
                                ? '받기'
                                : '출석',
                            style: petText(
                              15,
                              color: pet.attended
                                  ? PetColors.muted
                                  : PetColors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(height: 1, color: PetColors.line),
                    ),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Text('이번 주 미션', style: petText(18)),
                        PetPill(
                          '${pet.missions.where((m) => m['claimed'] == true).length}/3단계 완료',
                          color: const Color(0xFFF0F3F6),
                          ink: PetColors.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (c, b) {
                        final narrow =
                            b.maxWidth < 300 ||
                            MediaQuery.textScalerOf(c).scale(1) > 1.35;
                        return Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < 3; i++)
                              SizedBox(
                                width: narrow
                                    ? b.maxWidth
                                    : (b.maxWidth - 16) / 3,
                                child: _mission(i),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (widget.missionsOnly) ...[
              const SizedBox(height: 16),
              Text(
                '함께 활동은 기관이 참여 완료로 확인한 함께 참여 프로그램으로 집계해요.',
                style: petText(15, color: PetColors.secondary),
              ),
              if (widget.onOpenProgramMissions != null) ...[
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: widget.onOpenProgramMissions,
                  icon: const Icon(Icons.route_outlined),
                  label: const Text('프로그램별 주간 미션 보기'),
                ),
              ],
            ],
            if (!widget.missionsOnly) ...[
              const SizedBox(height: 24),
              _section('동네 프로그램'),
              PetCard(
                padding: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (pet.programs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '신청한 프로그램이 없어요. 가까운 활동을 찾아보세요.',
                          style: petText(
                            17,
                            color: PetColors.secondary,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                    for (final p in pet.programs) ...[
                      _program(p),
                      if (p != pet.programs.last)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Divider(height: 1, color: PetColors.line),
                        ),
                    ],
                    const SizedBox(height: 14),
                    PetCard(
                      color: const Color(0xFFF5F8FB),
                      padding: 12,
                      child: Text(
                        'ⓘ 신청만으로는 보상이 지급되지 않아요.\n기관에서 참여를 확인한 뒤 지급돼요.',
                        style: petText(15, color: PetColors.secondary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    PetPrimary('내 주변 프로그램 찾기', onTap: programs, light: true),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('광고 보상', style: petText(22)),
                  Text(
                    '원할 때만 · 오늘 ${2 - pet.ads}회 남음',
                    style: petText(14, color: PetColors.muted),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PetCard(
                padding: 16,
                child: Row(
                  children: [
                    _badge(
                      Icons.play_arrow_rounded,
                      PetColors.yellow,
                      PetColors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('짧은 광고 보기', style: petText(19)),
                          const SizedBox(height: 5),
                          const PetPill(
                            '+ 30 P',
                            color: PetColors.yellow,
                            ink: Color(0xFF946100),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: adLoading || pet.ads >= 2 ? null : ad,
                      child: Text(
                        adLoading
                            ? '준비 중'
                            : pet.ads >= 2
                            ? '내일 다시'
                            : pet.pendingAd != null
                            ? '보상 받기'
                            : '보기',
                        style: petText(17, color: PetColors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (pet.isPreview)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '디자인 미리보기 · 실제 데이터는 변경되지 않아요',
                  style: petText(14, color: PetColors.muted),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
  Widget _section(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(s, style: petText(22)),
  );
  Widget _badge(IconData icon, Color color, Color ink) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Icon(icon, color: ink, size: 28),
  );
  Widget _mission(int i) {
    final pet = widget.pet,
        m = pet.missions.length > i ? pet.missions[i] : <String, dynamic>{};
    final done = m['claimed'] == true, eligible = m['completed'] == true;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => !pet.adopted
          ? widget.onOpenPet?.call()
          : eligible
          ? reward('mission_reward', {'stage': i + 1})
          : petDialog(
              context,
              title: ['출석 3일', '모임 1회 참여', '프로그램 1회 참여'][i],
              message:
                  '${m['progress'] ?? 0}/${m['target'] ?? [3, 1, 1][i]} 완료했어요. 실제 출석과 기관의 참여 완료 기록으로 확인해요.',
            ),
      child: PetCard(
        padding: 12,
        color: done ? PetColors.mint : const Color(0xFFF7F9FB),
        border: Border.all(
          color: eligible && !done ? PetColors.blue : Colors.transparent,
          width: 1.5,
        ),
        child: Column(
          children: [
            Text(
              '${i + 1}단계${done
                  ? ' ✓'
                  : eligible
                  ? ' · 완료'
                  : ''}',
              style: petText(
                14,
                color: done ? PetColors.green : PetColors.blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ['출석\n3일', '함께 활동\n1회 참여', '프로그램\n1회 참여'][i],
              textAlign: TextAlign.center,
              style: petText(17),
            ),
            const SizedBox(height: 10),
            PetPill(
              done
                  ? '받음'
                  : i == 1
                  ? '+ 100 P'
                  : '+ ${i == 0 ? 10 : 30} EXP',
              color: done
                  ? const Color(0xFFECF1F3)
                  : i == 1
                  ? PetColors.yellow
                  : PetColors.lavender,
              ink: done
                  ? PetColors.muted
                  : i == 1
                  ? const Color(0xFF946100)
                  : PetColors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _program(Map<String, dynamic> p) {
    final completed = p['status'] == 'completed', paid = p['rewarded'] == true;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(
          paid ? Icons.check : Icons.schedule,
          paid ? PetColors.mint : PetColors.yellow,
          paid ? PetColors.green : PetColors.orange,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        ActivityDetailPage(programId: '${p['program_id']}'),
                  ),
                ),
                child: Text('${p['title']}', style: petText(19)),
              ),
              Text(
                '${p['place_name']} · ${completed ? '참여 확인 완료' : '기관 확인 대기'}',
                style: petText(14, color: PetColors.secondary),
              ),
              const SizedBox(height: 6),
              const Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  PetPill(
                    '+ 200 P',
                    color: PetColors.yellow,
                    ink: Color(0xFF946100),
                  ),
                  PetPill('+ 50 EXP'),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: completed && !paid && !widget.pet.busy
                      ? () => reward('program_reward', {'id': p['id']})
                      : null,
                  child: Text(
                    paid
                        ? '✓ 지급 완료'
                        : completed
                        ? '보상 받기'
                        : '기관 확인 대기',
                    style: petText(
                      15,
                      color: paid ? PetColors.green : PetColors.orange,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

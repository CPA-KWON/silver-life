import 'package:flutter/material.dart';

import '../attendance/attendance_controller.dart';
import '../pet/pet_design.dart';
import '../pet/pet_preview_controller.dart';
import 'activity_design.dart';

class ActivityWeeklyMissionsPage extends StatelessWidget {
  const ActivityWeeklyMissionsPage({
    super.key,
    required this.pet,
    this.onOpenPet,
    this.onOpenProgramMissions,
  });
  final PetPreviewController pet;
  final VoidCallback? onOpenPet, onOpenProgramMissions;
  Future<void> claim(BuildContext context, int stage) async {
    try {
      final r = await pet.run('mission_reward', {'stage': stage});
      if (!context.mounted) return;
      await AttendanceScope.maybeOf(context)?.refresh();
      if (!context.mounted) return;
      final home = await activityDialog(
        context,
        title: r.already ? '이미 받은 보상이에요' : '$stage단계 보상을 받았어요!',
        message: '${pet.name ?? '콩이'}가 쑥쑥 자라고 있어요.',
        icon: Icons.card_giftcard_outlined,
        color: PetColors.purple,
        action: '콩이 보러 가기',
        secondary: '닫기',
        rows: [
          ('받은 포인트', '+${r.points} P'),
          ('성장 경험치', '+${r.experience} EXP'),
        ],
      );
      if (home && context.mounted) onOpenPet?.call();
    } catch (_) {
      if (context.mounted) {
        await activityFailure(
          context,
          title: '보상을 받지 못했어요',
          message: '실제 미션 달성 여부와 앞 단계 보상 수령 상태를 확인해 주세요.',
        );
      }
    }
  }

  Future<void> attend(BuildContext context) async {
    try {
      await pet.run('attendance');
      if (context.mounted) await AttendanceScope.maybeOf(context)?.refresh();
    } catch (_) {
      if (context.mounted) {
        await activityFailure(context, title: '출석을 확인하지 못했어요');
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: pet,
    builder: (c, _) {
      final kst = pet.today; // Server-provided Korean calendar date.
      final start = DateTime(
        kst.year,
        kst.month,
        kst.day,
      ).subtract(Duration(days: kst.weekday - 1));
      final weekLogs = pet.logs.where(
        (l) =>
            l.kind == 'mission' &&
            !l.date.toUtc().add(const Duration(hours: 9)).isBefore(start),
      );
      final points = weekLogs.fold(0, (n, l) => n + l.points),
          xp = weekLogs.fold(0, (n, l) => n + l.experience);
      return ActivityScreen(
        title: '주간 미션',
        tint: ActivityColors.orange,
        child: RefreshIndicator(
          onRefresh: pet.load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              if (!pet.ready)
                ActivityEmpty(
                  pet.error == null ? '미션 정보를 확인하고 있어요' : '미션 정보를 불러오지 못했어요',
                  message: pet.error == null
                      ? '잠시만 기다려 주세요'
                      : '인터넷 연결을 확인해 주세요',
                  action: '다시 확인하기',
                  onAction: pet.load,
                )
              else ...[
                ActivityCard(
                  color: const Color(0xFFF5DFEF),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 80,
                        child: PetPhoto(pet: pet, height: 90, mood: 'greeting'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${pet.name ?? '콩이'}에게 줄 보상을 모아요',
                              style: petText(22),
                            ),
                            Text(
                              '이번 주 받은 보상',
                              style: petText(16, color: PetColors.secondary),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 7,
                              runSpacing: 5,
                              children: [
                                PetPill(
                                  '+ $points P',
                                  color: PetColors.yellow,
                                  ink: PetColors.orange,
                                ),
                                PetPill('+ $xp EXP'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!pet.adopted)
                  ActivityEmpty(
                    '콩이를 입양하면 미션 보상을 받을 수 있어요',
                    message: '홈에서 반려동물을 먼저 만나 주세요',
                    action: '반려동물 만나기',
                    onAction: onOpenPet,
                  ),
                ActivityCard(
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_available_outlined,
                        color: PetColors.green,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('오늘 출석', style: petText(21)),
                            Text(
                              pet.attendanceRewarded
                                  ? '출석 완료 · 내일 또 만나요'
                                  : '하루 한 번, 함께 자라요',
                              style: petText(15, color: PetColors.secondary),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed:
                            pet.busy || !pet.adopted || pet.attendanceRewarded
                            ? null
                            : () => attend(context),
                        child: Text(
                          pet.attendanceRewarded ? '✓ 출석 완료' : '출석하기',
                        ),
                      ),
                    ],
                  ),
                ),
                ActivityHeading(
                  '이번 주 미션',
                  color: PetColors.orange,
                  trailing: Text(
                    '${pet.missions.where((m) => m['claimed'] == true).length}/3단계',
                    style: petText(16, color: PetColors.secondary),
                  ),
                ),
                ActivityCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < 3; i++) _mission(context, i),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '함께 활동은 기관이 참여 완료로 확인한 함께 참여 프로그램으로 집계해요. 월요일 0시에 새 주가 시작돼요.',
                  style: petText(15, color: PetColors.secondary),
                ),
              ],
              const SizedBox(height: 18),
              ActivityCard(
                onTap: onOpenProgramMissions,
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, color: PetColors.purple),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('프로그램별 주간 미션 보기', style: petText(19)),
                          Text(
                            '내 조건에 맞는 프로그램 3개로 도전',
                            style: petText(15, color: PetColors.secondary),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: ActivityColors.muted,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _mission(BuildContext context, int i) {
    final m = pet.missions.length > i ? pet.missions[i] : <String, dynamic>{};
    final claimed = m['claimed'] == true, done = m['completed'] == true;
    final locked =
        i > 0 && pet.missions.take(i).any((m) => m['completed'] != true);
    final priorClaimed = pet.missions
        .take(i)
        .every((m) => m['claimed'] == true);
    final eligible = done && !claimed && priorClaimed;
    final color = claimed
        ? PetColors.green
        : eligible
        ? PetColors.orange
        : locked
        ? ActivityColors.muted
        : ActivityColors.blue;
    final emblem = CircleAvatar(
      radius: 21,
      backgroundColor: color.withValues(alpha: locked ? 0.25 : 1.0),
      child: claimed || eligible
          ? const Icon(Icons.check, color: Colors.white)
          : Text('${i + 1}', style: petText(19, color: Colors.white)),
    );
    final progress = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${i + 1}단계 · ${claimed
              ? '보상 받음'
              : done
              ? '달성!'
              : locked
              ? '진행 전'
              : '진행 중'}',
          style: petText(14, color: color),
        ),
        Text(['출석 3일', '함께 활동 1회', '프로그램 1회'][i], style: petText(19)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value:
                ((m['progress'] as num? ?? 0) /
                        (m['target'] as num? ?? [3, 1, 1][i]))
                    .clamp(0, 1)
                    .toDouble(),
            color: color,
            backgroundColor: PetColors.line,
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          locked
              ? '이전 단계를 마치면 열려요'
              : done && !priorClaimed
              ? '앞 단계 보상부터 받아주세요'
              : '${m['progress'] ?? 0}/${m['target'] ?? [3, 1, 1][i]}${i == 0 ? '일' : '회'}',
          style: petText(14, color: PetColors.secondary),
        ),
      ],
    );
    final Widget trailing = claimed
        ? const PetPill(
            '✓ 받음',
            color: PetColors.mint,
            ink: PetColors.green,
            fontSize: 13,
          )
        : eligible
        ? SizedBox(
            width: 90,
            child: ActivityButton(
              '보상 받기',
              color: PetColors.orange,
              onTap: pet.busy || !pet.adopted
                  ? null
                  : () => claim(context, i + 1),
            ),
          )
        : PetPill(
            i == 1 ? '+ 100 P' : '+ ${i == 0 ? 10 : 30} EXP',
            color: i == 1 ? PetColors.yellow : PetColors.lavender,
            ink: i == 1 ? PetColors.orange : PetColors.purple,
            fontSize: 13,
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ActivityCard(
        padding: 14,
        color: claimed
            ? const Color(0xFFE6F6EE)
            : eligible
            ? const Color(0xFFFFF1DA)
            : locked
            ? const Color(0xFFF5F8FA)
            : Colors.white,
        border: BorderSide(
          color: color.withValues(alpha: locked ? 0.15 : 1.0),
          width: 1.5,
        ),
        child: LayoutBuilder(
          builder: (c, b) {
            final compact =
                b.maxWidth < 275 || MediaQuery.textScalerOf(c).scale(1) > 1.35;
            return compact
                ? Row(
                    children: [
                      emblem,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            progress,
                            const SizedBox(height: 10),
                            trailing,
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      emblem,
                      const SizedBox(width: 12),
                      Expanded(child: progress),
                      const SizedBox(width: 10),
                      trailing,
                    ],
                  );
          },
        ),
      ),
    );
  }
}

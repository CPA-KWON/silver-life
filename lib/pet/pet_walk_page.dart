import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_walk_service.dart';
import 'pet_care_pages.dart';

class PetWalkPage extends StatefulWidget {
  const PetWalkPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetWalkPage> createState() => _WalkState();
}

class _WalkState extends State<PetWalkPage> with WidgetsBindingObserver {
  final service = PetWalkService();
  Timer? timer;
  int steps = 0, ticks = 0;
  bool active = false, paused = false, eligible = false, working = false;
  String? notice;
  DateTime? started;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => poll());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) poll(force: true);
  }

  Future<void> restore() async {
    final w = widget.pet.activeWalk;
    if (w != null) {
      active = true;
      steps = (w['steps'] as num?)?.toInt() ?? 0;
      eligible = w['eligible'] == true;
      started = DateTime.tryParse('${w['started_at']}');
    }
    await poll(force: true);
  }

  Future<void> poll({bool force = false}) async {
    if (!mounted || !active || working) return;
    try {
      if (!widget.pet.isPreview) {
        final data = await service.status();
        if (!mounted) return;
        // Ignore another session's stale local sensor values.
        if (data['session'] == widget.pet.activeWalk?['id']) {
          steps = (data['steps'] as num?)?.toInt() ?? steps;
          paused = data['paused'] == true;
          if (data['supported'] != true) {
            notice = '이 기기에는 걸음 센서가 없어요. 동네 시설 방문으로 완료할 수 있어요.';
          }
          if (data['active'] != true && !eligible) {
            notice = '기록이 멈춰 있어요. 이어 걷기를 눌러주세요.';
          }
          if (force || ++ticks % 5 == 0) {
            await widget.pet.run('walk_sync', {
              'id': widget.pet.activeWalk?['id'],
              'steps': steps,
              for (final k in ['lat', 'lng', 'accuracy', 'location_at'])
                if (data[k] != null) k: data[k],
            });
          }
        }
      }
      eligible = widget.pet.activeWalk?['eligible'] == true;
      if (eligible && !widget.pet.isPreview) await service.stop();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(() => notice = '진행 상황을 서버에 보내지 못했어요. 다시 연결되면 확인해요.');
      }
    }
  }

  Future<void> start() async {
    setState(() => working = true);
    try {
      if (widget.pet.activeWalk == null) await widget.pet.run('walk_start');
      if (!widget.pet.isPreview) {
        await service.start('${widget.pet.activeWalk!['id']}');
      }
      if (!mounted) return;
      setState(() {
        active = true;
        paused = false;
        notice = null;
        started =
            DateTime.tryParse('${widget.pet.activeWalk?['started_at']}') ??
            DateTime.now();
      });
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> pause() async {
    try {
      if (!widget.pet.isPreview) {
        if (paused) {
          await service.start('${widget.pet.activeWalk!['id']}');
        } else {
          await service.pause();
        }
      }
      if (mounted) setState(() => paused = !paused);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  Future<void> cancel() async {
    if (!await petDialog(
      context,
      title: '산책을 끝낼까요?',
      message: '완료 조건을 채우기 전에는 보상을 받을 수 없어요.',
      action: '산책 끝내기',
      secondary: '계속 걷기',
    )) {
      return;
    }
    try {
      await widget.pet.run('walk_cancel', {'id': widget.pet.activeWalk?['id']});
      await service.stop();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  Future<void> claim() async {
    try {
      final r = await widget.pet.run('walk_reward', {
        'id': widget.pet.activeWalk?['id'],
        'steps': steps,
      });
      if (!mounted) return;
      await petDialog(
        context,
        title: r.already ? '이미 받은 보상이에요' : '보상을 받았어요!',
        message: '${widget.pet.name}와 함께한 산책이 기록됐어요.',
        emblem: const Icon(
          Icons.card_giftcard,
          color: PetColors.purple,
          size: 40,
        ),
        rows: [
          ('포인트', '+${r.points} P'),
          ('성장 경험치', '+${r.experience} EXP'),
          ('지금 포인트', '${petNumber(widget.pet.points)}P'),
        ],
        color: PetColors.purple,
        action: '콩이에게 돌아가기',
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  Future<void> previewGoal() async {
    await widget.pet.run('walk_sync', {'steps': 2014});
    if (mounted) {
      setState(() {
        steps = 2014;
        eligible = true;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final pet = widget.pet;
    final complete = eligible || pet.walked;
    final minutes = started == null
        ? 0
        : DateTime.now().difference(started!).inMinutes;
    return PetScreen(
      fullscreen: true,
      colors: const [Color(0xFFE6F6ED), PetColors.background],
      footer: working
          ? const Center(child: CircularProgressIndicator())
          : complete
          ? PetPrimary(
              pet.walked ? '오늘 산책 보상 받음' : '보상 받기',
              onTap: pet.walked ? () => Navigator.pop(c) : claim,
            )
          : !active
          ? PetPrimary('산책 시작하기', onTap: start)
          : Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: pause,
                    child: Text(
                      paused ? '이어 걷기' : '잠시 멈추기',
                      style: petText(18, color: PetColors.secondary),
                    ),
                  ),
                ),
                Expanded(
                  child: PetPrimary('산책 끝내기', light: true, onTap: cancel),
                ),
              ],
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetHeader(
            complete
                ? '산책 완료'
                : active
                ? '산책 중'
                : '${pet.name}와 산책하기',
            pet: !active ? pet : null,
            trailing: active
                ? PetPill(
                    complete
                        ? '완료'
                        : paused
                        ? '잠시 쉬는 중'
                        : '걸음 수 확인 중',
                    color: PetColors.mint,
                    ink: PetColors.green,
                  )
                : null,
          ),
          SizedBox(
            height: 190,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: CustomPaint(
                painter: _Park(),
                child: Column(
                  children: [
                    if (active)
                      PetSpeech(complete ? '최고의 산책이었어요!' : '영차영차! 같이 걸어요'),
                    Expanded(
                      child: PetPhoto(
                        pet: pet,
                        height: 220,
                        mood: complete ? 'happy' : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!active && !complete) ...[
            PetCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('실제로 걸으면 ${pet.name}도 함께 걸어요', style: petText(22)),
                  const SizedBox(height: 8),
                  Text(
                    '휴대폰 걸음 수로 확인해요. 산책 중에는 화면을 꺼도 기록해요.',
                    style: petText(
                      17,
                      color: PetColors.secondary,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('완료 조건  둘 중 하나만 하면 돼요', style: petText(21)),
            const SizedBox(height: 12),
            PetCard(
              child: Column(
                children: [
                  _condition(Icons.route, '오늘 2,000걸음 걷기', '산책을 시작한 뒤의 걸음 수예요'),
                  const Divider(height: 30),
                  _condition(
                    Icons.location_on_outlined,
                    '동네 시설 1곳 다녀오기',
                    '시설 100m 안에서 2분 머물러요',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('완료 보상', style: petText(21)),
            const SizedBox(height: 12),
            PetCard(
              child: const Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  PetPill(
                    '+ 30 P',
                    color: PetColors.yellow,
                    ink: Color(0xFF916100),
                  ),
                  PetPill('+ 10 EXP'),
                  PetPill(
                    '하루 1번',
                    color: Colors.white,
                    ink: PetColors.secondary,
                  ),
                ],
              ),
            ),
          ] else if (complete) ...[
            PetCard(
              child: Column(
                children: [
                  const PetPill(
                    '✓ 완료 조건 달성',
                    color: PetColors.mint,
                    ink: PetColors.green,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '오늘 ${petNumber(steps)}걸음 걸었어요',
                    textAlign: TextAlign.center,
                    style: petText(26),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '걸음 수 확인이 끝났어요. 보상을 받아주세요.',
                    textAlign: TextAlign.center,
                    style: petText(18, color: PetColors.secondary),
                  ),
                  const SizedBox(height: 20),
                  Text('+ 30 P     + 10 EXP', style: petText(22)),
                ],
              ),
            ),
          ] else ...[
            PetCard(
              child: Column(
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: (steps / 2000).clamp(0, 1),
                            strokeWidth: 16,
                            color: PetColors.green,
                            backgroundColor: const Color(0xFFE2EEE7),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(petNumber(steps), style: petText(38)),
                            Text(
                              '/ 2,000걸음',
                              style: petText(20, color: PetColors.secondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '${math.max(0, 2000 - steps)}걸음 더 걸으면 완료예요',
                    textAlign: TextAlign.center,
                    style: petText(22),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$minutes분째 산책 중 · 화면을 꺼도 걸음을 기록해요',
                    textAlign: TextAlign.center,
                    style: petText(16, color: PetColors.secondary),
                  ),
                ],
              ),
            ),
          ],
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                notice!,
                style: petText(17, color: PetColors.secondary),
              ),
            ),
          if (pet.activeWalk?['facility_name'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '방문할 시설: ${pet.activeWalk!['facility_name']}',
                style: petText(17),
              ),
            ),
          if (pet.isPreview) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: active && !complete
                  ? previewGoal
                  : () => petDialog(
                      c,
                      title: '디자인 미리보기',
                      message: '실제 걸음이나 포인트가 아닌 화면 검토용 데이터예요.',
                    ),
              child: Text(
                active && !complete ? '미리보기: 완료 화면 확인' : '화면 미리보기 · 실제 기록 없음',
                style: petText(15, color: PetColors.secondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _condition(IconData icon, String title, String description) => Row(
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: PetColors.mint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: PetColors.green, size: 28),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: petText(19)),
            Text(
              description,
              style: petText(
                16,
                color: PetColors.secondary,
                weight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Park extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = const Color(0xFFD2EFDE);
    c.drawRect(Offset.zero & s, p);
    p.color = const Color(0xFF8FD2AB);
    for (final x in [.12, .25, .73, .88]) {
      c.drawOval(
        Rect.fromCenter(
          center: Offset(s.width * x, s.height * .65),
          width: s.width * .12,
          height: 65,
        ),
        p,
      );
    }
    p.color = const Color(0xFFB8E3CB);
    c.drawOval(
      Rect.fromLTWH(
        -s.width * .1,
        s.height * .72,
        s.width * 1.2,
        s.height * .5,
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

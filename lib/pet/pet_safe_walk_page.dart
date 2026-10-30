import '../core/points.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../facility/facility_catalog.dart';
import '../facility/facility_repository.dart';
import '../facility/naver_local_search.dart';
import 'pet_preview_controller.dart';
import 'pet_walk_service.dart';
import 'pet_walk_settings.dart';
import 'pet_design.dart';
import 'pet_care_pages.dart';

class PetWalkPage extends StatefulWidget {
  const PetWalkPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetWalkPage> createState() => _SafeWalkState();
}

class _SafeWalkState extends State<PetWalkPage> with WidgetsBindingObserver {
  final service = PetWalkService();
  late final settings = PetWalkSettings(
    widget.pet.isPreview ? 'preview' : service.owner,
  );
  Timer? timer;
  bool loading = true,
      working = false,
      polling = false,
      active = false,
      paused = false,
      showMap = false,
      eligible = false,
      finished = false,
      claimed = false;
  bool sensor = true,
      locationDenied = false,
      permanent = false,
      overdueShown = false;
  int steps = 0, ticks = 0;
  DateTime? started;
  String? notice;
  Map<String, dynamic>? position;
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
    if (s == AppLifecycleState.resumed) poll();
  }

  bool notificationAllowed = true;
  Future<void> restore() async {
    if (!widget.pet.isPreview) await settings.load();
    if (!widget.pet.isPreview) {
      notificationAllowed = await Permission.notification.isGranted;
    }
    final walk = widget.pet.activeWalk;
    if (walk != null) {
      active = true;
      steps = (walk['steps'] as num?)?.toInt() ?? 0;
      eligible = walk['eligible'] == true;
      final ended = settings.records
          .where((r) => r['id'] == walk['id'])
          .toList();
      if (ended.isNotEmpty) {
        finished = true;
        claimed = ended.first['rewarded'] == true;
      }
      started = DateTime.tryParse('${walk['started_at']}');
      if (settings.session != walk['id']) {
        settings.session = walk['id'];
        settings.pausedSeconds = 0;
        settings.pausedAt = null;
        await settings.save();
      }
    }
    if (!mounted) return;
    setState(() => loading = false);
    unawaited(poll());
    if (!widget.pet.isPreview && widget.pet.expansionEnabled) {
      // Retry summaries recorded offline before merging other device history.
      for (final record in settings.records.where((r) => r['synced'] != true)) {
        try {
          await widget.pet.repository!.client
              .rpc(
                'pet_record_walk',
                params: {'p_id': record['id'], 'p_seconds': record['seconds']},
              )
              .timeout(const Duration(seconds: 8));
          record['synced'] = true;
        } catch (_) {
          break;
        }
      }
      try {
        final rows = await widget.pet.repository!.client
            .from('pet_walk_summaries')
            .select('walk_id,steps,seconds,eligible,created_at')
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(const Duration(seconds: 8));
        for (final row in rows) {
          if (!settings.records.any((r) => r['id'] == row['walk_id'])) {
            settings.records.add({
              'id': row['walk_id'],
              'steps': row['steps'],
              'seconds': row['seconds'],
              'eligible': row['eligible'],
              'date': row['created_at'],
              'synced': true,
            });
          }
        }
        settings.records.sort(
          (a, b) => '${b['date']}'.compareTo('${a['date']}'),
        );
      } catch (_) {}
      await settings.save();
    }
    if (mounted) setState(() {});
  }

  Future<void> run(Future<void> Function() fn) async {
    if (working) return;
    setState(() => working = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> poll() async {
    if (!mounted || loading || working || polling || !active || finished) {
      return;
    }
    polling = true;
    try {
      if (!widget.pet.isPreview) {
        final data = await service.status();
        if (!mounted) return;
        if (data['session'] != widget.pet.activeWalk?['id']) {
          paused = true;
          notice = '기록을 이어가려면 이어 걷기를 눌러주세요.';
        } else {
          steps = (data['steps'] as num?)?.toInt() ?? steps;
          paused = data['paused'] == true;
          sensor = data['supported'] == true;
          position = data['lat'] == null ? null : data;
          if (data['active'] != true && !eligible) {
            paused = true;
            notice = '산책 기록이 멈췄어요. 이어 걷기를 눌러주세요.';
          }
          if (++ticks % 5 == 0 && !paused) {
            await widget.pet.run('walk_sync', {
              'id': widget.pet.activeWalk?['id'],
              'steps': steps,
              for (final key in ['lat', 'lng', 'accuracy', 'location_at'])
                if (data[key] != null) key: data[key],
            });
            notice = null;
          }
        }
      }
      eligible = widget.pet.activeWalk?['eligible'] == true;
      if (mounted) setState(() {});
      if (!overdueShown &&
          settings.returnAt != null &&
          DateTime.now().isAfter(settings.returnAt!)) {
        overdueShown = true;
        if (mounted) await overdue();
      }
    } catch (_) {
      if (mounted) {
        setState(() => notice = '서버에 연결하지 못했어요. 기록은 기기에 남겨요. 연결되면 다시 확인해요.');
      }
    } finally {
      polling = false;
    }
  }

  Future<void> start() async => run(() async {
    if (widget.pet.activeWalk == null) await widget.pet.run('walk_start');
    if (!widget.pet.isPreview) {
      await service.start(
        '${widget.pet.activeWalk!['id']}',
        returnAt: settings.returnAt,
        petName: widget.pet.name,
      );
    }
    settings.session = widget.pet.activeWalk?['id'];
    settings.pausedSeconds = 0;
    settings.pausedAt = null;
    await settings.save();
    if (mounted) {
      setState(() {
        active = true;
        paused = false;
        started =
            DateTime.tryParse('${widget.pet.activeWalk?['started_at']}') ??
            DateTime.now();
        notice = null;
      });
    }
  });
  Future<void> togglePause() async => run(() async {
    if (!widget.pet.isPreview) {
      if (paused) {
        await service.start(
          '${widget.pet.activeWalk!['id']}',
          returnAt: settings.returnAt,
          petName: widget.pet.name,
        );
      } else {
        await service.pause();
      }
    }
    if (paused) {
      if (settings.pausedAt != null) {
        settings.pausedSeconds += DateTime.now()
            .difference(settings.pausedAt!)
            .inSeconds;
      }
      settings.pausedAt = null;
    } else {
      settings.pausedAt = DateTime.now();
    }
    await settings.save();
    if (mounted) setState(() => paused = !paused);
  });
  Future<void> end() async {
    if (eligible) {
      await finish(true);
      return;
    }
    final yes = await petDialog(
      context,
      title: '오늘은 여기까지 해도 괜찮아요',
      message: '산책 기록은 남겨요. 완료 조건을 채우기 전에는 보상이 없어요.',
      action: '산책 끝내기',
      secondary: '조금 더 걸을게요',
    );
    if (yes && mounted) await finish(false);
  }

  Future<void> finish(bool completed) async => run(() async {
    // Stop locally first, including offline: ending a walk must never wait for a server.
    if (!widget.pet.isPreview) await service.stop();
    final entry = {
      'id': settings.session,
      'date': DateTime.now().toIso8601String(),
      'steps': steps,
      'seconds': elapsed,
      'eligible': completed,
      'rewarded': false,
      'daily_limit': completed && widget.pet.walked,
    };
    settings.pausedAt ??= DateTime.now();
    settings.records.removeWhere((r) => r['id'] == entry['id']);
    settings.records.insert(0, entry);
    await settings.save();
    if (!widget.pet.isPreview && widget.pet.expansionEnabled) {
      try {
        await widget.pet.repository!.client
            .rpc(
              'pet_record_walk',
              params: {'p_id': entry['id'], 'p_seconds': entry['seconds']},
            )
            .timeout(const Duration(seconds: 8));
        entry['synced'] = true;
        await settings.save();
      } catch (_) {
        notice = '기기에 기록을 저장했어요. 다음 연결 때 서버에도 저장해요.';
      }
    }
    if (mounted) {
      setState(() {
        finished = true;
        paused = true;
      });
    }
    if (!completed || widget.pet.walked) {
      if (completed && widget.pet.walked) claimed = true;
      try {
        await widget.pet.run('walk_cancel', {
          'id': widget.pet.activeWalk?['id'],
        });
      } catch (_) {
        notice = '기기에는 종료 기록을 저장했어요. 서버 종료 확인은 다시 연결되면 진행해요.';
      }
    }
  });
  Future<void> claim() async => run(() async {
    final result = await widget.pet.run('walk_reward', {
      'id': settings.session,
      'steps': steps,
    });
    if (settings.records.isNotEmpty &&
        settings.records.first['id'] == settings.session) {
      settings.records.first['rewarded'] = true;
    }
    await settings.save();
    if (!mounted) return;
    setState(() => claimed = true);
    await petDialog(
      context,
      title: result.already ? '이미 받은 보상이에요' : '보상을 받았어요!',
      message: '첫 산책 배지도 옷장에서 확인해보세요.',
      rows: [
        ('포인트', '+${pointAmount(result.points)}P'),
        ('성장 경험치', '+${result.experience}EXP'),
      ],
      color: PetColors.green,
    );
  });
  int get elapsed =>
      started == null ? 0 : settings.activeSeconds(started!, DateTime.now());
  String get timeLabel => '${elapsed ~/ 60}분';
  bool get fresh =>
      position != null &&
      DateTime.now().millisecondsSinceEpoch -
              ((position!['location_at'] as num?)?.toInt() ?? 0) <
          90000;
  Future<void> phone() async {
    if (settings.phone.isEmpty) {
      await contact();
      return;
    }
    final yes = await petDialog(
      context,
      title: '${settings.name}님에게 전화할까요?',
      message: settings.phone,
      action: '전화 앱 열기',
      secondary: '취소',
    );
    if (!yes) return;
    try {
      if (!await launchUrl(
        Uri(
          scheme: 'tel',
          path: settings.phone.replaceAll(RegExp(r'[\s()-]'), ''),
        ),
      )) {
        throw StateError('전화 앱을 열 수 없어요. 번호를 직접 확인해주세요.');
      }
    } catch (e) {
      if (mounted) {
        await showPetFailure(
          context,
          StateError('전화 앱을 열 수 없어요. ${settings.phone} 번호로 연락해주세요.'),
        );
      }
    }
  }

  Future<void> contact() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _WalkContactPage(settings: settings, onCall: phone),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<Position?> locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      locationDenied =
          permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever;
      permanent = permission == LocationPermission.deniedForever;
      if (locationDenied) throw StateError('위치 권한을 허용하면 주변 시설과 지도를 볼 수 있어요.');
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (e) {
      if (mounted) {
        await showPetFailure(
          context,
          e is StateError ? e : StateError('현재 위치를 확인하지 못했어요. 위치 설정을 확인해주세요.'),
        );
      }
      return null;
    }
  }

  Future<void> destination() async {
    final p = await locate();
    if (p == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => _WalkDestinations(
          lat: p.latitude,
          lng: p.longitude,
          onSelect: (f) async {
            final id = await ensureFacility(f);
            settings.destination = {
              'id': id,
              'name': f.name,
              'address': f.address,
              'lat': f.lat,
              'lng': f.lng,
            };
            await settings.save();
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> returnTime() async {
    final selected = await showModalBottomSheet<Duration>(
      context: petModalContext(context),
      useRootNavigator: false,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('몇 시쯤 돌아올 예정인가요?', style: petText(24)),
            const SizedBox(height: 16),
            for (final min in [30, 60, 90, 120])
              TextButton(
                onPressed: () => Navigator.pop(c, Duration(minutes: min)),
                child: Text('$min분 뒤', style: petText(21)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(c, Duration.zero),
              child: const Text('시간 정하지 않기'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    settings.returnAt = selected == Duration.zero
        ? null
        : DateTime.now().add(selected);
    overdueShown = false;
    await settings.save();
    if (!widget.pet.isPreview && active && !finished) {
      await service.configureReturn(settings.returnAt, widget.pet.name);
    }
    if (mounted) setState(() {});
  }

  Future<void> overdue() async {
    await showModalBottomSheet<void>(
      context: petModalContext(context),
      useRootNavigator: false,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('괜찮으세요?', style: petText(28)),
            Text('정해둔 귀가 시간이 지났어요. 잠시 쉬거나 가족·지인에게 연락해보세요.', style: petText(18)),
            const SizedBox(height: 16),
            PetPrimary(
              '가족·지인에게 전화',
              color: PetColors.green,
              onTap: () {
                Navigator.pop(c);
                phone();
              },
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                returnTime();
              },
              child: const Text('시간 바꾸기'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('이대로 계속 걷기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> share() async {
    final text =
        '${widget.pet.name}와 산책했어요!\n$steps걸음 · $timeLabel\nSilver Life';
    final yes = await petDialog(
      context,
      title: '이렇게 공유할까요?',
      message: '$text\n\n연락처·좌표·목적지 주소는 공유하지 않아요.',
      action: '공유할 앱 고르기',
      secondary: '취소',
    );
    if (yes && mounted) {
      try {
        await SharePlus.instance.share(
          ShareParams(
            text: text,
            sharePositionOrigin: Rect.fromLTWH(
              0,
              0,
              MediaQuery.sizeOf(context).width,
              100,
            ),
          ),
        );
      } catch (e) {
        if (mounted) await showPetFailure(context, StateError('공유창을 열지 못했어요.'));
      }
    }
  }

  Future<void> history() async => showModalBottomSheet<void>(
    context: petModalContext(context),
    useRootNavigator: false,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (c) => SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('산책 기록 · 이 기기', style: petText(25)),
          if (settings.records.isEmpty)
            Text('산책을 마치면 여기에 모아드려요.', style: petText(18)),
          for (final r in settings.records)
            ListTile(
              title: Text(
                '${r['steps']}걸음 · ${(r['seconds'] as num).toInt() ~/ 60}분',
              ),
              subtitle: Text(
                '${DateTime.tryParse('${r['date']}')?.toLocal().toString().split('.')[0] ?? ''}\n${r['rewarded'] == true
                    ? '보상 받음'
                    : r['daily_limit'] == true
                    ? '오늘 산책 보상은 이미 받았어요'
                    : r['eligible'] == true
                    ? '완료 조건 달성'
                    : '기록만 저장'}',
              ),
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext c) {
    final pet = widget.pet;
    Widget row(IconData icon, String title, String value, VoidCallback tap) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: PetColors.green),
          title: Text(title, style: petText(17)),
          subtitle: Text(value, style: petText(15, color: PetColors.secondary)),
          trailing: const Icon(Icons.chevron_right),
          onTap: tap,
        );
    final done = finished;
    return PetScreen(
      fullscreen: true,
      colors: const [Color(0xFFE4F5EB), PetColors.background],
      footer: loading
          ? const LinearProgressIndicator()
          : done
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PetPrimary(
                  claimed
                      ? '확인'
                      : eligible
                      ? '보상 받기'
                      : '오늘도 수고했어요',
                  color: PetColors.green,
                  onTap: working
                      ? null
                      : eligible && !claimed
                      ? claim
                      : () => Navigator.pop(c),
                ),
                TextButton(
                  onPressed: working ? null : share,
                  child: const Text('산책 결과 공유'),
                ),
              ],
            )
          : active
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PetPrimary(
                  '가족·지인에게 전화',
                  light: true,
                  color: PetColors.green,
                  icon: Icons.phone_outlined,
                  onTap: phone,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: working ? null : togglePause,
                        child: Text(
                          paused ? '이어 걷기' : '일시정지',
                          style: petText(18),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PetPrimary(
                        '산책 종료',
                        onTap: working ? null : end,
                        color: PetColors.ink,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : PetPrimary(
              '산책 시작하기',
              color: PetColors.green,
              onTap: working || loading ? null : start,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetHeader(
            done
                ? '산책 완료'
                : active
                ? '${pet.name}와 산책'
                : '${pet.name}와 산책하기',
            pet: active ? null : pet,
            trailing: active
                ? PetPill(
                    done
                        ? '기록 저장'
                        : paused
                        ? '잠시 쉬는 중'
                        : '기록 중',
                    color: PetColors.mint,
                    ink: PetColors.green,
                  )
                : null,
          ),
          if (pet.isPreview)
            Text(
              '디자인 미리보기 · 실제 걸음/위치를 기록하지 않아요',
              style: petText(14, color: PetColors.muted),
            ),
          if (pet.isPreview && active && !finished)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() => steps = 1240),
                  child: const Text('미리보기: 진행 중'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    steps = 2014;
                    eligible = true;
                    pet.activeWalk?['eligible'] = true;
                  }),
                  child: const Text('미리보기: 완료 조건 달성'),
                ),
              ],
            ),
          if (working) const LinearProgressIndicator(),
          if (notice != null)
            PetCard(
              color: PetColors.yellow,
              child: Text(notice!, style: petText(16)),
            ),
          if (active) ...[
            PetCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '산책 시작 후 걸음',
                          style: petText(15, color: PetColors.secondary),
                        ),
                        Text('${petNumber(steps)}걸음', style: petText(36)),
                        Text(
                          '목표 2,000걸음 · ${steps >= 2000 ? 0 : 2000 - steps}걸음 남음',
                          style: petText(15, color: PetColors.green),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: PetPhoto(
                      pet: pet,
                      height: 105,
                      mood: done ? 'happy' : 'walk',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PetCard(
              child: Column(
                children: [
                  row(Icons.timer_outlined, '산책 시간', timeLabel, history),
                  row(
                    Icons.flag_outlined,
                    '목적지',
                    settings.destination?['name'] as String? ?? '목적지 없이 걷기',
                    destination,
                  ),
                ],
              ),
            ),
            if (!sensor)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '걸음 센서를 지원하지 않아요. 시설 100m 안에서 2분 머물기로 완료할 수 있어요.',
                  style: petText(16, color: PetColors.blue),
                ),
              ),
            if (settings.returnAt != null &&
                DateTime.now().isAfter(settings.returnAt!))
              PetCard(
                color: PetColors.yellow,
                child: TextButton(
                  onPressed: returnTime,
                  child: const Text('귀가 예정 시간이 지났어요 · 시간 바꾸기'),
                ),
              ),
            const SizedBox(height: 12),
            if (!done)
              PetCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    row(
                      Icons.map_outlined,
                      '지도',
                      showMap ? '접기' : '펼치기',
                      () => setState(() => showMap = !showMap),
                    ),
                    if (showMap)
                      _WalkMap(
                        position: position,
                        destination: settings.destination,
                      ),
                    Text(
                      position == null
                          ? '위치를 확인 중이에요. 전화와 종료는 사용할 수 있어요.'
                          : !fresh
                          ? '최근 위치가 오래됐어요. 위치를 다시 확인해주세요.'
                          : (position!['accuracy'] as num) > 60
                          ? '위치 정확도가 낮아요. 시설 방문 확인이 어려울 수 있어요.'
                          : '최근 위치 확인 · 직선거리 기준',
                      style: petText(14, color: PetColors.secondary),
                    ),
                  ],
                ),
              ),
            if (done) ...[
              const SizedBox(height: 16),
              PetCard(
                child: Column(
                  children: [
                    Text(
                      eligible ? '완료 조건 달성!' : '오늘은 여기까지 걸었어요',
                      style: petText(26),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      eligible
                          ? '3,000P · 10EXP · 하루 한 번'
                          : '기록은 저장했어요. 이번 산책은 보상 조건을 채우지 못했어요.',
                      style: petText(18, color: PetColors.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            PetCard(
              color: const Color(0xFFCEEDDB),
              child: Column(
                children: [
                  const PetSpeech('오늘도 같이 걸어요!'),
                  PetPhoto(
                    pet: pet,
                    height: 145,
                    mood: 'walk',
                    live3d: true,
                    interactive: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('오늘 목표', style: petText(22)),
            const SizedBox(height: 10),
            PetCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('완료 조건 · 둘 중 하나만 하면 돼요', style: petText(18)),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (c, b) {
                      final cards = <Widget>[
                        PetCard(
                          color: PetColors.mint,
                          padding: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.directions_walk,
                                color: PetColors.green,
                              ),
                              Text('2,000걸음 걷기', style: petText(18)),
                              Text(
                                '산책 시작 후 걸음 수',
                                style: petText(14, color: PetColors.secondary),
                              ),
                            ],
                          ),
                        ),
                        PetCard(
                          color: PetColors.mint,
                          padding: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.flag_outlined,
                                color: PetColors.green,
                              ),
                              Text('동네 시설 들르기', style: petText(18)),
                              Text(
                                '시설 100m 안에서 2분 머무르기',
                                style: petText(14, color: PetColors.secondary),
                              ),
                            ],
                          ),
                        ),
                      ];
                      return b.maxWidth < 300 ||
                              MediaQuery.textScalerOf(c).scale(1) > 1.2
                          ? Column(
                              children: [
                                cards[0],
                                const SizedBox(height: 8),
                                cards[1],
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: cards[0]),
                                const SizedBox(width: 10),
                                Expanded(child: cards[1]),
                              ],
                            );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    children: [
                      PetPill(
                        '+3,000P',
                        color: PetColors.yellow,
                        ink: PetColors.orange,
                      ),
                      PetPill('+10EXP'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '2,000걸음은 앱 보상 기준이에요. 몸 상태에 맞춰 쉬어가세요.',
                    style: petText(14, color: PetColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text('선택 준비', style: petText(22)),
            Text(
              '등록하지 않아도 바로 걸을 수 있어요.',
              style: petText(15, color: PetColors.secondary),
            ),
            const SizedBox(height: 10),
            PetCard(
              child: Column(
                children: [
                  row(
                    Icons.flag_outlined,
                    '목적지',
                    settings.destination?['name'] as String? ?? '목적지 없이 걸어요',
                    destination,
                  ),
                  if (settings.destination != null)
                    TextButton(
                      onPressed: () async {
                        settings.destination = null;
                        await settings.save();
                        if (mounted) setState(() {});
                      },
                      child: const Text('목적지 지우기'),
                    ),
                  row(
                    Icons.phone_outlined,
                    '가족·지인에게 전화',
                    settings.phone.isEmpty
                        ? '연락처를 등록해요'
                        : '${settings.name} · ${settings.phone}',
                    contact,
                  ),
                  row(
                    Icons.schedule,
                    '귀가 예정 시간',
                    settings.returnAt == null
                        ? '정하지 않았어요'
                        : '${settings.returnAt!.hour}:${settings.returnAt!.minute.toString().padLeft(2, '0')}',
                    returnTime,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (!notificationAllowed)
              PetCard(
                color: PetColors.yellow,
                child: Text(
                  '휴대폰 알림이 꺼져 있어요. 귀가 시간은 앱을 열었을 때 확인할 수 있어요.',
                  style: petText(16),
                ),
              ),
            Text('나가기 전에', style: petText(22)),
            const SizedBox(height: 10),
            PetCard(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  Text('휴대폰을 챙겼나요?', style: petText(16)),
                  Text('밝고 익숙한 길로 걸어요', style: petText(16)),
                  Text('불편하면 쉬어가요', style: petText(16)),
                ],
              ),
            ),
            if (locationDenied)
              TextButton(
                onPressed: permanent ? Geolocator.openAppSettings : locate,
                child: Text(permanent ? '설정에서 위치 권한 바꾸기' : '위치 다시 확인'),
              ),
            TextButton(onPressed: history, child: const Text('산책 기록 보기')),
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _WalkDestinations extends StatefulWidget {
  const _WalkDestinations({
    required this.lat,
    required this.lng,
    required this.onSelect,
  });
  final double lat, lng;
  final Future<void> Function(FacilityResult) onSelect;
  @override
  State<_WalkDestinations> createState() => _DestinationState();
}

class _DestinationState extends State<_WalkDestinations> {
  late Future<FacilitySearchBatch> results = searchFacilityCatalog(
    category: '전체',
    lat: widget.lat,
    lng: widget.lng,
  );
  String query = '';
  bool saving = false;
  @override
  Widget build(BuildContext c) => PetScreen(
    fullscreen: true,
    colors: const [PetColors.mint, PetColors.background],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PetHeader('목적지 고르기'),
        TextField(
          decoration: const InputDecoration(
            hintText: '시설 이름으로 찾기',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        Text('현재 위치 기준 · 직선거리', style: petText(15, color: PetColors.secondary)),
        FutureBuilder<FacilitySearchBatch>(
          future: results,
          builder: (c, s) {
            if (s.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (s.hasError) {
              return PetPrimary(
                '시설 다시 불러오기',
                onTap: () => setState(
                  () => results = searchFacilityCatalog(
                    category: '전체',
                    lat: widget.lat,
                    lng: widget.lng,
                  ),
                ),
              );
            }
            final rows = s.data!.results
                .where(
                  (f) => f.name.contains(query) || f.address.contains(query),
                )
                .toList();
            if (rows.isEmpty) {
              return PetCard(
                child: Text(
                  '주변에 해당하는 시설이 없어요. 목적지 없이 걸어도 괜찮아요.',
                  style: petText(18),
                ),
              );
            }
            return Column(
              children: [
                for (final f in rows)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: PetCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(f.name, style: petText(20)),
                        subtitle: Text(
                          '${f.address}\n${f.distanceMeters.round()}m · 직선거리',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: saving
                            ? null
                            : () async {
                                setState(() => saving = true);
                                try {
                                  await widget.onSelect(f);
                                  if (c.mounted) Navigator.pop(c);
                                } catch (e) {
                                  if (c.mounted) await showPetFailure(c, e);
                                } finally {
                                  if (mounted) setState(() => saving = false);
                                }
                              },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

class _WalkMap extends StatefulWidget {
  const _WalkMap({required this.position, required this.destination});
  final Map<String, dynamic>? position, destination;
  @override
  State<_WalkMap> createState() => _WalkMapState();
}

class _WalkMapState extends State<_WalkMap> {
  NaverMapController? map;
  String? error;
  bool ready = false;
  Timer? timeout;
  @override
  void initState() {
    super.initState();
    timeout = Timer(const Duration(seconds: 15), () {
      if (mounted && !ready) {
        setState(() => error = '지도를 불러오지 못했어요. 전화와 산책 종료는 계속 사용할 수 있어요.');
      }
    });
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  NLatLng point(Map<String, dynamic> p) =>
      NLatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
  Future<void> update() async {
    if (map == null) return;
    try {
      await map!.clearOverlays(type: NOverlayType.marker);
      if (widget.position != null) {
        await map!.addOverlay(
          NMarker(
            id: 'me',
            position: point(widget.position!),
            caption: const NOverlayCaption(text: '최근 확인 위치'),
          ),
        );
      }
      if (widget.destination != null) {
        await map!.addOverlay(
          NMarker(
            id: 'destination',
            position: point(widget.destination!),
            caption: NOverlayCaption(text: '${widget.destination!['name']}'),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = '지도 위치 표시를 갱신하지 못했어요.');
    }
  }

  @override
  void didUpdateWidget(_WalkMap old) {
    super.didUpdateWidget(old);
    update();
  }

  @override
  Widget build(BuildContext c) {
    if (widget.position == null) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('현재 위치를 확인하면 지도를 보여드려요.')),
      );
    }
    if (error != null) {
      return SizedBox(
        height: 180,
        child: Center(child: Text(error!, style: petText(16))),
      );
    }
    return SizedBox(
      height: 240,
      child: NaverMap(
        options: NaverMapViewOptions(
          initialCameraPosition: NCameraPosition(
            target: point(widget.position!),
            zoom: 15,
          ),
          locationButtonEnable: false,
        ),
        onMapReady: (controller) {
          map = controller;
          ready = true;
          timeout?.cancel();
          update();
        },
      ),
    );
  }
}

class _WalkContactPage extends StatefulWidget {
  const _WalkContactPage({required this.settings, required this.onCall});
  final PetWalkSettings settings;
  final Future<void> Function() onCall;
  @override
  State<_WalkContactPage> createState() => _WalkContactState();
}

class _WalkContactState extends State<_WalkContactPage> {
  late final name = TextEditingController(text: widget.settings.name),
      number = TextEditingController(text: widget.settings.phone);
  final form = GlobalKey<FormState>();
  late String relation = widget.settings.relation;
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    number.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final yes = await petDialog(
      context,
      title: '이 번호가 맞나요?',
      message:
          '${name.text.trim()}${relation.isEmpty ? '' : ' ($relation)'}\n${number.text.trim()}',
      action: '맞아요, 저장할게요',
      secondary: '번호 고치기',
    );
    if (!yes || !mounted) return;
    setState(() => saving = true);
    try {
      widget.settings.name = name.text.trim();
      widget.settings.phone = number.text.trim();
      widget.settings.relation = relation;
      await widget.settings.save();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext c) => PetScreen(
    fullscreen: true,
    colors: const [PetColors.mint, PetColors.background],
    footer: PetPrimary(
      '번호 확인하기',
      onTap: saving ? null : save,
      color: PetColors.green,
    ),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PetHeader('연락처 등록'),
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('① 이름 · 필수', style: petText(18)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: name,
                  maxLength: 20,
                  style: petText(20),
                  decoration: const InputDecoration(hintText: '이름'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? '이름을 입력해주세요.' : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('② 관계 · 선택', style: petText(18)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final label in [
                      '자녀',
                      '배우자',
                      '형제자매',
                      '친구·이웃',
                      '보호자',
                      '기타',
                    ])
                      ChoiceChip(
                        label: Text(label, style: petText(16)),
                        selected: relation == label,
                        onSelected: (yes) =>
                            setState(() => relation = yes ? label : ''),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PetCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('③ 전화번호 · 필수', style: petText(18)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: number,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  style: petText(20),
                  decoration: const InputDecoration(hintText: '010-0000-0000'),
                  validator: (v) => PetWalkSettings.validPhone(v ?? '')
                      ? null
                      : '전화번호를 확인해주세요.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PetCard(
            color: const Color(0xFFE4F1FA),
            child: Text(
              '이름과 번호는 이 기기에만 저장해요. 산책할 때 연락할 사람을 직접 등록하며, 자동으로 알리거나 위치를 공유하지 않아요.',
              style: petText(16, color: PetColors.secondary),
            ),
          ),
          if (widget.settings.phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final yes = await petDialog(
                  c,
                  title: '연락처를 지울까요?',
                  message: '산책 기록은 그대로 남아요.',
                  action: '지우기',
                  secondary: '그대로 두기',
                );
                if (!yes) return;
                widget.settings.name = '';
                widget.settings.phone = '';
                widget.settings.relation = '';
                await widget.settings.save();
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('등록한 연락처 지우기'),
            ),
          ],
        ],
      ),
    ),
  );
}

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pet_repository.dart';
import 'pet_catalog.dart';

class PetOutcome {
  const PetOutcome({
    this.points = 0,
    this.experience = 0,
    this.already = false,
    this.data = const {},
  });
  final int points, experience;
  final bool already;
  final PetJson data;
}

class PetLog {
  const PetLog(
    this.title,
    this.kind,
    this.date, {
    this.points = 0,
    this.experience = 0,
  });
  final String title, kind;
  final DateTime date;
  final int points, experience;
}

class PetFood {
  const PetFood(this.id, this.name, this.price, this.fullness, this.xp);
  final String id, name;
  final int price, fullness, xp;
  static const all = [
    PetFood('food', '기본 사료', 0, 1, 0),
    PetFood('sweet', '고구마 간식', 0, 2, 5),
    PetFood('gum', '우유 껌', 50, 1, 10),
    PetFood('cake', '특별 케이크', 120, 3, 20),
  ];
}

/// Live in MainShell. A repository-free instance is an explicitly labelled
/// design preview, and can never write to the real wallet.
class PetPreviewController extends ChangeNotifier {
  PetPreviewController({this.repository, int initialPoints = 1250})
    : points = initialPoints;
  final PetRepository? repository;
  bool get isPreview => repository == null;
  bool ready = false, busy = false;
  String? error, name;
  int points,
      experience = 0,
      fullness = 2,
      stage = 0,
      freeFoodUsed = 0,
      ads = 0;
  bool attended = false, walked = false;
  DateTime? adoptedAt;
  DateTime today = DateTime.now();
  final owned = <String>{};
  final worn = <String>{};
  final snacks = <String, int>{'sweet': 2};
  final logs = <PetLog>[];
  final records = <String>[];
  final programs = <PetJson>[];
  final missions = <PetJson>[];
  final stageDates = <int, DateTime>{};
  PetJson? activeWalk;
  String? pendingAd;
  bool _disposed = false;
  String? _pendingId, _pendingAction;
  PetJson? _pendingPayload;

  String species = 'dog';
  bool get isCat => species == 'cat';
  String get defaultName => isCat ? '나비' : '콩이';
  List<PetFood> get foods => isCat
      ? const [
          PetFood('food', '기본 사료', 0, 1, 0),
          PetFood('sweet', '촉촉 참치', 0, 2, 5),
          PetFood('gum', '연어 트릿', 50, 1, 10),
          PetFood('cake', '닭고기 수프', 120, 3, 20),
        ]
      : PetFood.all;
  bool adsEnabled = false;
  bool storeEnabled = false;
  bool expansionEnabled = false;
  bool get adopted => name != null;
  bool get fed => freeFoodUsed > 0;
  bool get attendanceRewarded =>
      logs.any((l) => l.kind == 'attendance' && _sameDay(l.date, today));
  bool get programCompleted => programs.any((p) => p['rewarded'] == true);
  String get stageName => ['아기', '성장기', '성체'][stage];
  String get assetStage => ['baby', 'junior', 'adult'][stage];
  int get nextExperience => stage == 0 ? 200 : 500;
  bool get canGrow => stage < 2 && experience >= nextExperience;
  double get progress =>
      stage == 2 ? 1 : (experience / nextExperience).clamp(0, 1);
  int get daysTogether => adoptedAt == null
      ? 0
      : DateTime(today.year, today.month, today.day)
                .difference(
                  DateTime(adoptedAt!.year, adoptedAt!.month, adoptedAt!.day),
                )
                .inDays +
            1;
  int get todayPoints => logs
      .where((l) => _sameDay(l.date, today))
      .fold(0, (n, l) => n + (l.points > 0 ? l.points : 0));
  int get todayExperience => logs
      .where((l) => _sameDay(l.date, today))
      .fold(0, (n, l) => n + l.experience);
  int count(String kind) => logs.where((l) => l.kind == kind).length;
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> load() async {
    if (busy) return;
    if (isPreview) {
      ready = true;
      _notify();
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      _read(await repository!.load());
      ready = true;
    } catch (_) {
      error = '반려동물 서버를 연결하지 못했어요. 서버 설정 후 다시 시도해주세요.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<PetOutcome> run(String action, [PetJson payload = const {}]) async {
    if (busy) throw StateError('처리 중이에요. 잠시만 기다려주세요.');
    busy = true;
    error = null;
    _notify();
    try {
      if (isPreview) return _demo(action, payload);
      // A retry of an ambiguous response reuses the same server idempotency key.
      if (_pendingAction != action || !mapEquals(_pendingPayload, payload)) {
        _pendingId = PetRepository.requestId();
        _pendingAction = action;
        _pendingPayload = Map.of(payload);
      }
      final result = await repository!.act(action, payload, _pendingId!);
      _read(
        result['state'] == null
            ? result
            : Map<String, dynamic>.from(result['state']),
      );
      _pendingId = _pendingAction = null;
      _pendingPayload = null;
      final outcome = result['outcome'] as Map? ?? {};
      return PetOutcome(
        points: (outcome['points'] as num?)?.toInt() ?? 0,
        experience: (outcome['experience'] as num?)?.toInt() ?? 0,
        already: outcome['already'] == true,
        data: Map<String, dynamic>.from(outcome),
      );
    } catch (e) {
      if (e is StateError) rethrow;
      if (e is PostgrestException && e.code == 'P0001') {
        _pendingId = _pendingAction = null;
        _pendingPayload = null;
        throw StateError(e.message);
      }
      error = '처리 결과를 확인하지 못했어요. 다시 시도해도 같은 요청은 중복 처리하지 않아요.';
      throw StateError(error!);
    } finally {
      busy = false;
      _notify();
    }
  }

  void _read(PetJson data) {
    final p = data['pet'] as Map?;
    name = p?['name'] as String?;
    species = p?['species'] == 'cat' ? 'cat' : 'dog';
    expansionEnabled = data['expansion'] == true;
    adsEnabled = data['ads_enabled'] == true;
    storeEnabled = data['store_enabled'] == true;
    stage = (p?['stage'] as num?)?.toInt() ?? 0;
    experience = (p?['experience'] as num?)?.toInt() ?? 0;
    fullness = (p?['fullness'] as num?)?.toInt() ?? 2;
    adoptedAt = DateTime.tryParse('${p?['adopted_at']}')?.toLocal();
    today = DateTime.tryParse('${data['today']}') ?? DateTime.now();
    points = (data['balance'] as num?)?.toInt() ?? 0;
    final d = data['daily'] as Map? ?? {};
    freeFoodUsed = (d['free_feeds'] as num?)?.toInt() ?? 0;
    ads = (d['ads'] as num?)?.toInt() ?? 0;
    walked = d['walked'] == true;
    attended = data['attended'] == true;
    owned
      ..clear()
      ..addAll((data['owned'] as List? ?? []).cast<String>());
    worn
      ..clear()
      ..addAll((data['worn'] as List? ?? []).cast<String>());
    snacks
      ..clear()
      ..addAll({
        for (final row in data['snacks'] as List? ?? [])
          '${row['item']}': (row['quantity'] as num).toInt(),
      });
    programs
      ..clear()
      ..addAll(
        (data['programs'] as List? ?? []).map(
          (v) => Map<String, dynamic>.from(v),
        ),
      );
    missions
      ..clear()
      ..addAll(
        (data['missions'] as List? ?? []).map(
          (v) => Map<String, dynamic>.from(v),
        ),
      );
    logs
      ..clear()
      ..addAll(
        (data['history'] as List? ?? []).map(
          (v) => PetLog(
            '${v['title']}',
            '${v['kind']}',
            DateTime.parse('${v['created_at']}').toLocal(),
            points: (v['points'] as num?)?.toInt() ?? 0,
            experience: (v['experience'] as num?)?.toInt() ?? 0,
          ),
        ),
      );
    records
      ..clear()
      ..addAll(logs.map((l) => l.title));
    stageDates.clear();
    (p?['stage_dates'] as Map? ?? {}).forEach((k, v) {
      final date = DateTime.tryParse('$v');
      if (date != null) stageDates[int.parse('$k')] = date.toLocal();
    });
    pendingAd = data['pending_ad'] as String?;
    activeWalk = data['walk'] == null
        ? null
        : Map<String, dynamic>.from(data['walk']);
  }

  void _log(String title, String kind, {int p = 0, int xp = 0}) {
    logs.insert(0, PetLog(title, kind, today, points: p, experience: xp));
    records.insert(0, title);
  }

  void _spend(int p) {
    if (points < p) throw StateError('포인트가 부족해요. 오늘의 활동에서 모아보세요.');
    points -= p;
  }

  PetOutcome _demo(String action, PetJson payload) {
    var p = 0, xp = 0;
    switch (action) {
      case 'adopt':
        final v = '${payload['name'] ?? ''}'.trim();
        if (v.isEmpty || v.runes.length > 6) {
          throw StateError('이름은 1~6자로 지어주세요.');
        }
        if (adopted) throw StateError('이미 함께하는 반려동물이 있어요.');
        species = payload['species'] == 'cat' ? 'cat' : 'dog';
        name = v;
        adoptedAt = today;
        stageDates[0] = today;
        _log('$v를 입양했어요', 'adopt');
      case 'rename':
        final v = '${payload['name'] ?? ''}'.trim();
        if (v.isEmpty || v.runes.length > 6) {
          throw StateError('이름은 1~6자로 지어주세요.');
        }
        name = v;
      case 'feed':
        final item = foods.singleWhere((f) => f.id == payload['item']);
        if (item.id == 'food') {
          if (freeFoodUsed >= 3) throw StateError('오늘의 무료 사료를 모두 먹었어요.');
          freeFoodUsed++;
        } else if (item.id == 'sweet') {
          if ((snacks['sweet'] ?? 0) < 1) throw StateError('보유한 고구마 간식이 없어요.');
          snacks['sweet'] = snacks['sweet']! - 1;
        } else {
          _spend(item.price);
          p = -item.price;
        }
        xp = item.xp;
        experience += xp;
        fullness = (fullness + item.fullness).clamp(0, 5);
        _log(
          '${item.name}${item.id == 'food' ? '를' : '을'} 먹었어요',
          'feed',
          p: p,
          xp: xp,
        );
      case 'preview_purchase':
        final added = PetItem.find('${payload['item']}');
        if (added == null || !added.premium || !added.compatible(species)) {
          throw StateError('테스트 상품을 확인해주세요.');
        }
        if (owned.contains(added.id)) return const PetOutcome(already: true);
        owned.add(added.id);
        _log('${added.name} 테스트 구매 · 실제 결제 없음', 'purchase');
      case 'buy':
        final id = '${payload['item']}';
        if (owned.contains(id)) return const PetOutcome(already: true);
        final added = PetItem.find(id);
        if (added != null) {
          if (!added.compatible(species)) throw StateError('다른 동물 전용 아이템이에요.');
          if (stage < added.minStage) throw StateError('성장기가 되면 열려요.');
          if (added.source != 'points') throw StateError('아이템 획득 방법을 확인해주세요.');
          _spend(added.price);
          owned.add(id);
          _log('${added.name}를 샀어요', 'purchase', p: -added.price);
          return PetOutcome(points: -added.price);
        }
        if (id == 'rain') throw StateError('레인코트 착용 자료를 준비하고 있어요.');
        if (id == 'winter' && stage < 1) throw StateError('성장기가 되면 열려요.');
        _spend(itemPrices[id]!);
        p = -itemPrices[id]!;
        owned.add(id);
        _log('${itemNames[id]}를 샀어요', 'purchase', p: p);
      case 'wear':
        final selected = (payload['items'] as List).cast<String>().toSet();
        if (!owned.containsAll(selected)) throw StateError('보유한 옷만 입힐 수 있어요.');
        if (selected.map(PetItem.slotFor).toSet().length != selected.length) {
          throw StateError('같은 위치에는 하나만 입힐 수 있어요.');
        }
        if (selected.any(
          (id) =>
              PetItem.find(id) != null &&
              (!PetItem.find(id)!.compatible(species) ||
                  stage < PetItem.find(id)!.minStage),
        )) {
          throw StateError('지금 입을 수 없는 아이템이에요.');
        }
        if (selected.contains('knit') && selected.contains('winter')) {
          throw StateError('옷은 한 벌만 입힐 수 있어요.');
        }
        worn
          ..clear()
          ..addAll(selected);
        _log('꾸미기를 바꿨어요', 'outfit');
      case 'attendance':
        if (attended) return const PetOutcome(already: true);
        attended = true;
        p = 1;
        xp = 10;
        points += p;
        experience += xp;
        _log('오늘 출석했어요', 'attendance', p: p, xp: xp);
      case 'walk_start':
        activeWalk = {
          'id': 'preview-walk',
          'started_at': DateTime.now().toIso8601String(),
          'steps': 0,
          'eligible': false,
        };
        return const PetOutcome(data: {'session': 'preview-walk'});
      case 'walk_sync':
        activeWalk?['steps'] = payload['steps'] ?? 0;
        activeWalk?['eligible'] = (payload['steps'] as int? ?? 0) >= 2000;
      case 'walk_cancel':
        activeWalk = null;
      case 'ad_session':
        return const PetOutcome(data: {'session': 'preview-ad'});
      case 'mission_reward':
        final m = missions.firstWhere(
          (m) => m['stage'] == payload['stage'],
          orElse: () => {},
        );
        if (m['completed'] != true) throw StateError('미션을 먼저 완료해주세요.');
        if (m['claimed'] == true) return const PetOutcome(already: true);
        m['claimed'] = true;
        p = 100;
        points += 100;
        _log('주간 미션을 완료했어요', 'mission', p: p);
      case 'walk_reward':
        if (walked) return const PetOutcome(already: true);
        walked = true;
        activeWalk = null;
        owned.add('${species}_first_walk_badge');
        p = 30;
        xp = 10;
        points += p;
        experience += xp;
        _log('${payload['steps'] ?? 2000}걸음 산책', 'walk', p: p, xp: xp);
      case 'grow':
        if (!canGrow) throw StateError('성장 경험치를 조금 더 모아주세요.');
        stage++;
        stageDates[stage] = today;
        _log('$stageName가 되었어요', 'growth');
      case 'preview_ready':
        if (!isPreview) throw StateError('미리보기에서만 사용할 수 있어요.');
        experience = stage == 0 ? 200 : 500;
      case 'program_reward':
        final id = '${payload['id']}';
        final row = programs.firstWhere((p) => p['id'] == id, orElse: () => {});
        if (row['status'] != 'completed') {
          throw StateError('기관의 참여 완료 확인이 필요해요.');
        }
        if (row['rewarded'] == true) return const PetOutcome(already: true);
        row['rewarded'] = true;
        p = 200;
        xp = 50;
        points += p;
        experience += xp;
        _log('${row['title']} 참여 확인', 'program', p: p, xp: xp);
      case 'ad_claim':
        if (ads >= 2) throw StateError('오늘 광고 보상을 모두 받았어요.');
        ads++;
        p = 20;
        points += p;
        _log('광고 보상을 받았어요', 'ad', p: p);
      default:
        throw StateError('연결을 준비하고 있어요.');
    }
    return PetOutcome(points: p, experience: xp);
  }

  // Explicit design-review tools, never available to a live repository.
  void adopt(String value) {
    if (!isPreview) throw StateError('서버 연결을 사용해주세요.');
    _demo('adopt', {'name': value});
    ready = true;
    _notify();
  }

  void previewStage(int value) {
    if (!isPreview) return;
    stage = value;
    experience = [0, 200, 500][value];
    _notify();
  }

  void reset() {
    if (!isPreview) return;
    name = null;
    species = 'dog';
    points = 1250;
    experience = stage = freeFoodUsed = ads = 0;
    fullness = 2;
    attended = walked = false;
    adoptedAt = null;
    owned.clear();
    worn.clear();
    logs.clear();
    records.clear();
    stageDates.clear();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static const itemNames = {
    'hat': '털모자',
    'knit': '줄무늬 니트',
    'winter': '겨울 니트',
    'flower': '꽃핀',
    'rain': '레인코트',
  };
  static const itemPrices = {
    'hat': 150,
    'knit': 250,
    'winter': 300,
    'flower': 100,
    'rain': 400,
  };
}

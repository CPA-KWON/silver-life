import 'package:flutter/foundation.dart';

/// Screen prototype only. Never calls Supabase or the real point wallet.
/// Owned by MainShell so changing tabs retains the preview until sign-out.
class PetPreviewController extends ChangeNotifier {
  String? name;
  int points = 20;
  int experience = 0;
  int fullness = 2;
  bool attended = false, fed = false, walked = false, programCompleted = false;
  int ads = 0;
  final owned = <String>{};
  final worn = <String>{};
  final records = <String>[];
  bool get adopted => name != null;
  int get stage => experience >= 600
      ? 2
      : experience >= 150
      ? 1
      : 0;
  String get stageName => ['아기', '성장기', '성체'][stage];
  String get assetStage => ['baby', 'junior', 'adult'][stage];
  int get nextExperience => stage == 0 ? 150 : 600;
  double get progress => stage == 2 ? 1 : experience / nextExperience;
  void adopt(String value) {
    final next = value.trim();
    if (next.isEmpty || next.runes.length > 6) {
      throw StateError('이름은 1~6자로 지어주세요.');
    }
    name = next;
    _record('$next와 처음 만났어요');
  }

  void attendance() {
    if (attended) return;
    attended = true;
    points += 1;
    experience += 5;
    _record('출석했어요 · +1P · +5 경험치');
  }

  void feed({bool special = false}) {
    if (special) _spend(3);
    if (!special && fed) throw StateError('오늘 무료 사료는 이미 먹었어요.');
    fullness = (fullness + (special ? 2 : 1)).clamp(0, 5);
    final gain = fed ? 0 : 5;
    experience += gain;
    fed = true;
    _record('${special ? '특별 간식' : '기본 사료'}을 먹었어요 · +$gain 경험치');
  }

  void purchase(String id) {
    if (owned.contains(id)) return;
    _spend(itemPrices[id]!);
    owned.add(id);
    _record('${itemNames[id]}를 샀어요');
  }

  void wear(String id, {bool remove = false}) {
    if (!owned.contains(id)) throw StateError('먼저 아이템을 구매해주세요.');
    remove ? worn.remove(id) : worn.add(id);
    _record('${itemNames[id]}${remove ? '를 벗었어요' : '를 입었어요'}');
  }

  void walk() {
    if (walked) return;
    walked = true;
    points += 2;
    experience += 10;
    _record('산책 완료 상황을 확인했어요 · +2P · +10 경험치');
  }

  void completeProgram() {
    if (programCompleted) return;
    programCompleted = true;
    points += 5;
    experience += 30;
    _record('기관 참여 완료 상황을 확인했어요 · +5P · +30 경험치');
  }

  void advert() {
    if (ads >= 2) throw StateError('오늘 광고 보상을 모두 받았어요.');
    ads++;
    points++;
    _record('광고 보상 상황을 확인했어요 · +1P');
  }

  void previewStage(int value) {
    experience = [0, 150, 600][value];
    notifyListeners();
  }

  void reset() {
    name = null;
    points = 20;
    experience = 0;
    fullness = 2;
    attended = fed = walked = programCompleted = false;
    ads = 0;
    owned.clear();
    worn.clear();
    records.clear();
    notifyListeners();
  }

  void _spend(int amount) {
    if (points < amount) throw StateError('포인트가 부족해요. 오늘의 활동에서 모아보세요.');
    points -= amount;
  }

  void _record(String text) {
    records.insert(0, text);
    notifyListeners();
  }

  static const itemNames = {'hat': '털모자', 'knit': '줄무늬 니트', 'flower': '꽃핀'};
  static const itemPrices = {'hat': 10, 'knit': 20, 'flower': 5};
}

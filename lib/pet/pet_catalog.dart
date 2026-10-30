/// Stable identifiers shared with pet_expansion.sql. Prices are server-authoritative.
class PetItem {
  const PetItem(
    this.id,
    this.name,
    this.species,
    this.slot,
    this.source,
    this.price, {
    this.minStage = 0,
  });
  final String id, name, species, slot, source;
  final int price, minStage;
  bool get premium => source == 'play';
  bool get activity => source == 'activity';
  bool compatible(String kind) => species == kind;
  String get thumbnail => 'assets/pet/expansion/${id}_thumb.png';
  String fitting(int stage, {String angle = 'angle'}) {
    final age = ['baby', 'teen', 'adult'][stage];
    final suffix = stage == 1 && ['front', 'back'].contains(angle)
        ? '_$angle'
        : '';
    return 'assets/pet/expansion/${id}_$age$suffix.png';
  }

  String get productId => 'silverlife.$id';
  static PetItem? find(String id) {
    for (final i in all) {
      if (i.id == id) return i;
    }
    return null;
  }

  static String slotFor(String id) =>
      find(id)?.slot ??
      switch (id) {
        'hat' || 'flower' => 'head',
        'knit' || 'winter' || 'rain' => 'body',
        _ => id,
      };
  static const all = <PetItem>[
    PetItem('dog_walk_vest', '동네 산책 조끼', 'dog', 'body', 'points', 150),
    PetItem('dog_flower_cardigan', '꽃무늬 가디건', 'dog', 'body', 'points', 180),
    PetItem('dog_raincoat', '노란 우비', 'dog', 'body', 'points', 200, minStage: 1),
    PetItem('dog_winter_coat', '겨울 누빔 코트', 'dog', 'body', 'play', 0),
    PetItem('dog_outing_overall', '나들이 멜빵옷', 'dog', 'body', 'play', 0),
    PetItem(
      'dog_walk_hat',
      '산책 챙모자',
      'dog',
      'head',
      'points',
      100,
      minStage: 1,
    ),
    PetItem('dog_flower_pin', '꽃 장식', 'dog', 'head', 'points', 80),
    PetItem('dog_ribbon', '체크 리본', 'dog', 'neck', 'points', 100),
    PetItem('dog_first_walk_badge', '첫 산책 배지', 'dog', 'badge', 'activity', 0),
    PetItem('dog_outing_scarf', '나들이 스카프', 'dog', 'neck', 'play', 0),
    PetItem('cat_walk_vest', '고양이 산책 조끼', 'cat', 'body', 'points', 150),
    PetItem('cat_stripe_knit', '줄무늬 니트', 'cat', 'body', 'points', 150),
    PetItem('cat_raincoat', '연두 우비', 'cat', 'body', 'points', 200, minStage: 1),
    PetItem('cat_flower_cardigan', '꽃 가디건', 'cat', 'body', 'play', 0),
    PetItem('cat_outing_overall', '나들이 멜빵옷', 'cat', 'body', 'play', 0),
    PetItem(
      'cat_beret',
      '귀가 보이는 베레모',
      'cat',
      'head',
      'points',
      100,
      minStage: 1,
    ),
    PetItem('cat_flower_pin', '작은 꽃핀', 'cat', 'head', 'points', 80),
    PetItem('cat_ribbon', '체크 리본', 'cat', 'neck', 'points', 100),
    PetItem('cat_first_walk_badge', '첫 산책 배지', 'cat', 'badge', 'activity', 0),
    PetItem('cat_moon_scarf', '달무늬 스카프', 'cat', 'neck', 'play', 0),
  ];
}

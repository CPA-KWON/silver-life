import 'package:flutter/material.dart';

import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_character.dart';

Future<PetFood?> showPetFoodPicker(
  BuildContext context,
  PetPreviewController pet,
) => showModalBottomSheet<PetFood>(
  context: petModalContext(context),
  useRootNavigator: false,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (c) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: PetColors.line,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('간식 고르기', style: petText(25))),
            PetPoints(pet),
          ],
        ),
        const SizedBox(height: 20),
        _FoodChoices(pet: pet),
      ],
    ),
  ),
);

class _FoodChoices extends StatefulWidget {
  const _FoodChoices({required this.pet});
  final PetPreviewController pet;
  @override
  State<_FoodChoices> createState() => _FoodChoicesState();
}

class _FoodChoicesState extends State<_FoodChoices> {
  String selected = 'food';
  @override
  Widget build(BuildContext c) {
    final pet = widget.pet,
        food = PetFood.all.singleWhere((f) => f.id == selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (c, b) {
            final columns =
                MediaQuery.textScalerOf(c).scale(1) > 1.25 || b.maxWidth < 330
                ? 1
                : 2;
            final width = (b.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final f in PetFood.all)
                  SizedBox(
                    width: width,
                    height: columns == 2 ? 180 : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => setState(() => selected = f.id),
                      child: PetCard(
                        color: selected == f.id
                            ? const Color(0xFFFFF8EB)
                            : const Color(0xFFF5F7FA),
                        padding: 12,
                        border: Border.all(
                          color: selected == f.id
                              ? const Color(0xFFF8A817)
                              : Colors.transparent,
                          width: 2,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                FoodDrawing(f.id, size: 48),
                                const SizedBox(height: 8),
                                Text(f.name, style: petText(20)),
                                const SizedBox(height: 3),
                                Text(
                                  f.id == 'food'
                                      ? '하루 3번 무료 · ${3 - pet.freeFoodUsed}번 남음'
                                      : f.id == 'sweet'
                                      ? '보유한 간식'
                                      : '${f.price}P',
                                  style: petText(
                                    14,
                                    color: PetColors.secondary,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    PetPill(
                                      '배부름 +${f.fullness}',
                                      fontSize: 12,
                                      horizontal: 8,
                                      color: PetColors.yellow,
                                      ink: const Color(0xFF9E6100),
                                    ),
                                    if (f.xp > 0)
                                      PetPill(
                                        '+ ${f.xp} EXP',
                                        fontSize: 12,
                                        horizontal: 8,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                            if (f.id == 'sweet')
                              Positioned(
                                right: 0,
                                top: 0,
                                child: PetPill(
                                  '보유 ${pet.snacks['sweet'] ?? 0}',
                                  fontSize: 12,
                                  horizontal: 8,
                                  color: PetColors.mint,
                                  ink: PetColors.green,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        PetPrimary('${food.name} 주기', onTap: () => Navigator.pop(c, food)),
      ],
    );
  }
}

Future<void> showPetFailure(BuildContext c, Object error) => petDialog(
  c,
  title: error is StateError && error.message.toString().contains('부족')
      ? '포인트가 부족해요'
      : '다시 확인해주세요',
  message: error is StateError
      ? error.message
      : '처리하지 못했어요. 연결을 확인하고 다시 시도해주세요.',
  emblem: const Icon(Icons.info_outline, color: PetColors.blue, size: 38),
).then((_) {});

class PetWardrobePage extends StatefulWidget {
  const PetWardrobePage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetWardrobePage> createState() => _WardrobeState();
}

class _WardrobeState extends State<PetWardrobePage> {
  String category = '옷', selected = '';
  String view = 'angle';
  late final Set<String> draft = Set.of(widget.pet.worn);
  bool native = false;
  final categories = {
    '모자': ['hat'],
    '옷': ['knit', 'winter', 'rain'],
    '액세서리': ['flower'],
  };
  Future<void> choose(String id) async {
    final pet = widget.pet;
    if (id == 'winter' && pet.stage < 1) {
      await petDialog(
        context,
        title: '성장기가 되면 열려요',
        message: '성장 경험치를 모아 콩이를 성장시켜주세요.',
        emblem: const Icon(
          Icons.lock_outline,
          color: PetColors.purple,
          size: 40,
        ),
      );
      return;
    }
    if (id == 'rain') {
      await petDialog(
        context,
        title: pet.stage < 2 ? '성체에서 열려요' : '레인코트는 준비 중이에요',
        message: '착용 이미지가 준비되면 추가할게요.',
        emblem: const Icon(
          Icons.lock_outline,
          size: 40,
          color: PetColors.muted,
        ),
      );
      return;
    }
    setState(() {
      selected = id;
      if (category == '옷') {
        draft.remove('knit');
        draft.remove('winter');
      }
      draft.add(id);
    });
  }

  Future<void> apply() async {
    final pet = widget.pet, id = selected;
    try {
      if (!pet.owned.contains(id)) {
        final price = PetPreviewController.itemPrices[id]!;
        if (!await petDialog(
          context,
          title: '${PetPreviewController.itemNames[id]}를 살까요?',
          message: '사고 나면 바로 입혀 볼 수 있어요.',
          emblem: ItemArt(id),
          rows: [
            ('가격', '${price}P'),
            ('지금 포인트', '${petNumber(pet.points)}P'),
            ('구매 후 남는 포인트', '${petNumber(pet.points - price)}P'),
          ],
          action: '구매하기',
          secondary: '취소',
        )) {
          return;
        }
        await pet.run('buy', {'item': id});
        if (!mounted) return;
        await petDialog(
          context,
          title: '구매했어요!',
          message: '${PetPreviewController.itemNames[id]}를 옷장에 넣었어요.',
          emblem: ItemArt(id),
          action: '입혀보기',
        );
      } else {
        await pet.run('wear', {'items': draft.toList()});
        if (!mounted) return;
        await petDialog(
          context,
          title: '잘 어울려요!',
          message: '꾸미기를 적용했어요.',
          emblem: const Icon(
            Icons.check_circle_outline,
            color: PetColors.green,
            size: 42,
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) await showPetFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: widget.pet,
    builder: (c, _) {
      final pet = widget.pet;
      return PetScreen(
        fullscreen: true,
        colors: const [
          Color(0xFFFBEFF5),
          Color(0xFFF4F0FF),
          PetColors.background,
        ],
        footer: selected.isEmpty
            ? Text(
                '입혀볼 옷을 골라 주세요',
                textAlign: TextAlign.center,
                style: petText(18, color: PetColors.secondary),
              )
            : Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => setState(() {
                        draft
                          ..clear()
                          ..addAll(pet.worn);
                        selected = '';
                      }),
                      child: const Text('되돌리기'),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: PetPrimary(
                      pet.owned.contains(selected)
                          ? '입히기 완료'
                          : '${PetPreviewController.itemPrices[selected]}P에 구매하기',
                      onTap: pet.busy ? null : apply,
                    ),
                  ),
                ],
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetHeader('옷 입히기', pet: pet),
            PetCard(
              color: const Color(0xFFF7F0F7),
              padding: 8,
              child: Column(
                children: [
                  if (selected.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PetPill(
                        '미리보기 중',
                        color: PetColors.pinkTint,
                        ink: PetColors.pink,
                      ),
                    ),
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 40),
                        child: native
                            ? PetCharacter(pet: pet, outfit: draft, height: 270)
                            : PetPhoto(
                                pet: pet,
                                outfit: draft,
                                view: view,
                                height: 300,
                              ),
                      ),
                      Positioned(
                        right: 0,
                        top: 8,
                        child: Column(
                          children: [
                            for (final v in [
                              ('front', '앞'),
                              ('angle', '비스듬'),
                              ('back', '뒤'),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: InkWell(
                                  onTap: () => setState(() => view = v.$1),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: view == v.$1
                                                ? PetColors.pink
                                                : PetColors.line,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                        child: PetPhoto(
                                          pet: pet,
                                          view: v.$1,
                                          outfit: draft,
                                          height: 52,
                                        ),
                                      ),
                                      Text(
                                        v.$2,
                                        style: petText(
                                          13,
                                          color: PetColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => native = !native),
                    icon: const Icon(Icons.rotate_right),
                    label: Text(native ? '원본 모습 보기' : '좌우로 돌리기'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final cat in categories.keys)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilledButton(
                        onPressed: () => setState(() {
                          category = cat;
                          selected = '';
                        }),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 12,
                          ),
                          backgroundColor: category == cat
                              ? PetColors.ink
                              : Colors.white,
                          foregroundColor: category == cat
                              ? Colors.white
                              : PetColors.secondary,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          cat,
                          style: petText(
                            18,
                            color: category == cat
                                ? Colors.white
                                : PetColors.secondary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (c, b) {
                final columns = MediaQuery.textScalerOf(c).scale(1) > 1.4
                    ? 1
                    : 3;
                final width = (b.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final id in categories[category]!)
                      SizedBox(
                        width: width,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(22),
                          onTap: () => choose(id),
                          child: PetCard(
                            padding: 12,
                            color: Colors.white,
                            border: Border.all(
                              color: selected == id
                                  ? PetColors.blue
                                  : Colors.transparent,
                              width: 2,
                            ),
                            child: Column(
                              children: [
                                SizedBox(
                                  height: 64,
                                  child:
                                      id == 'rain' ||
                                          id == 'winter' && pet.stage < 1
                                      ? const Icon(
                                          Icons.lock_outline,
                                          size: 44,
                                          color: Color(0xFFB5BFCB),
                                        )
                                      : ItemArt(id),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  PetPreviewController.itemNames[id]!,
                                  textAlign: TextAlign.center,
                                  style: petText(
                                    17,
                                    color: id == 'rain'
                                        ? PetColors.muted
                                        : PetColors.ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  id == 'rain' ||
                                          id == 'winter' && pet.stage < 1
                                      ? (pet.stage < 2 ? '성체에서 열림' : '준비 중')
                                      : pet.worn.contains(id)
                                      ? '착용 중'
                                      : pet.owned.contains(id)
                                      ? '보유 중'
                                      : '${PetPreviewController.itemPrices[id]}P',
                                  textAlign: TextAlign.center,
                                  style: petText(
                                    15,
                                    color: pet.owned.contains(id)
                                        ? PetColors.green
                                        : const Color(0xFF946100),
                                  ),
                                ),
                                if (pet.owned.contains(id))
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => draft.remove(id)),
                                    child: const Text('벗기기'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}

class ItemArt extends StatelessWidget {
  const ItemArt(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext c) {
    final image = Image.asset(
      'assets/pet/items/${id == 'winter' ? 'knit' : id}.png',
      fit: BoxFit.contain,
    );
    return id == 'winter'
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix([
              .3,
              .7,
              0,
              0,
              0,
              .2,
              .4,
              .1,
              0,
              0,
              .3,
              .5,
              .3,
              0,
              0,
              0,
              0,
              0,
              1,
              0,
            ]),
            child: image,
          )
        : image;
  }
}

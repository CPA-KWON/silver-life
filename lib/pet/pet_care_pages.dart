import '../core/points.dart';

import 'package:flutter/material.dart';

import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_shop_page.dart';

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
        food = pet.foods.singleWhere((f) => f.id == selected);
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
                for (final f in pet.foods)
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
                                FoodDrawing(f.id, size: 48, isCat: pet.isCat),
                                const SizedBox(height: 8),
                                Text(f.name, style: petText(20)),
                                const SizedBox(height: 3),
                                Text(
                                  f.id == 'food'
                                      ? '하루 3번 무료 · ${3 - pet.freeFoodUsed}번 남음'
                                      : f.id == 'sweet'
                                      ? '보유한 간식'
                                      : '${pointAmount(f.price)}P',
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

class PetWardrobePage extends StatelessWidget {
  const PetWardrobePage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  Widget build(BuildContext context) => PetShopPage(pet: pet);
}

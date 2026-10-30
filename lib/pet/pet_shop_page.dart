import '../core/points.dart';

import 'package:flutter/material.dart';

import 'pet_catalog.dart';
import 'pet_design.dart';
import 'pet_preview_controller.dart';
import 'pet_care_pages.dart';
import 'pet_ads_service.dart';
import 'pet_billing_service.dart';

class PetShopPage extends StatefulWidget {
  const PetShopPage({super.key, required this.pet});
  final PetPreviewController pet;
  @override
  State<PetShopPage> createState() => _ShopState();
}

class _ShopState extends State<PetShopPage> {
  late final billing = PetBillingService(widget.pet);
  late Set<String> preview = Set.of(widget.pet.worn);
  String section = '새 아이템', category = '전체', source = '전체';
  bool working = false;
  final legacy = const [
    PetItem('hat', '털모자', 'dog', 'head', 'points', 150),
    PetItem('knit', '줄무늬 니트', 'dog', 'body', 'points', 250),
    PetItem('winter', '겨울 니트', 'dog', 'body', 'points', 300, minStage: 1),
    PetItem('flower', '꽃핀', 'dog', 'head', 'points', 100),
  ];
  @override
  void initState() {
    super.initState();
    if (!widget.pet.isPreview && !widget.pet.expansionEnabled) {
      widget.pet.load();
    }
    billing.initialize(
      PetItem.all.where((i) => i.premium).map((i) => i.productId).toSet(),
    );
  }

  @override
  void dispose() {
    billing.dispose();
    super.dispose();
  }

  Future<void> act(Future<void> Function() fn) async {
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

  Future<void> choose(PetItem item) async {
    final pet = widget.pet;
    if (!item.compatible(pet.species)) {
      await petDialog(
        context,
        title: '다른 친구 전용이에요',
        message: '이 아이템은 ${item.species == 'cat' ? '고양이' : '강아지'}에게 맞춰 만들었어요.',
      );
      return;
    }
    if (pet.stage < item.minStage) {
      await petDialog(
        context,
        title: '성장기가 되면 열려요',
        message: '활동하고 돌보면 더 다양한 옷을 입을 수 있어요.',
      );
      return;
    }
    final conflict = preview
        .where((id) => id != item.id && PetItem.slotFor(id) == item.slot)
        .toList();
    if (conflict.isNotEmpty) {
      final yes = await petDialog(
        context,
        title: '같은 위치에는 하나만 입힐 수 있어요',
        message: '지금 아이템을 ${item.name}로 바꿔서 입혀볼까요?',
        action: '바꿔 입혀보기',
        secondary: '그대로 두기',
      );
      if (!yes || !mounted) return;
    }
    final next = Set<String>.of(preview)
      ..removeWhere((id) => PetItem.slotFor(id) == item.slot)
      ..add(item.id);
    setState(() => preview = next);
    await showModalBottomSheet<void>(
      context: petModalContext(context),
      useRootNavigator: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) {
          final owned = pet.owned.contains(item.id),
              product = billing.products[item.productId];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(item.name, style: petText(26)),
                const SizedBox(height: 12),
                PetPhoto(
                  pet: pet,
                  height: 220,
                  outfit: {item.id},
                  live3d: true,
                  interactive: true,
                ),
                Text(
                  '${item.species == 'cat' ? '고양이' : '강아지'} 전용 · ${item.minStage == 0 ? '아기부터' : '성장기부터'} · 영구 소장',
                  style: petText(16, color: PetColors.secondary),
                ),
                const SizedBox(height: 16),
                if (item.activity && !owned)
                  Text('산책 완료 보상을 받으면 첫 산책 배지를 선물로 받아요.', style: petText(18)),
                if (item.premium && !owned) ...[
                  Text(
                    pet.isPreview
                        ? '예시 1,200원 · 실제 결제 없음'
                        : product?.price ?? '판매 준비 중',
                    style: petText(24, color: PetColors.blue),
                  ),
                  Text(
                    'Google Play로 구매하는 꾸미기 아이템이에요. 포인트와 별개예요.',
                    style: petText(16, color: PetColors.secondary),
                  ),
                ],
                if (!owned && !item.activity && !item.premium)
                  Text(
                    '${pointAmount(item.price)}P · 지금 ${pointAmount(pet.points)}P',
                    style: petText(21),
                  ),
                const SizedBox(height: 18),
                PetPrimary(
                  owned
                      ? '이 모습으로 입히기'
                      : item.activity
                      ? '산책으로 받는 선물'
                      : item.premium
                      ? (pet.isPreview
                            ? '테스트 결제 화면 보기'
                            : product == null
                            ? '판매 준비 중'
                            : '${product.price} · Google Play로 구매')
                      : '${pointAmount(item.price)}P로 구매',
                  onTap:
                      working ||
                          pet.busy ||
                          item.activity && !owned ||
                          item.premium &&
                              !owned &&
                              product == null &&
                              !pet.isPreview
                      ? null
                      : () async {
                          if (owned) {
                            Navigator.pop(c);
                            await act(() async {
                              await pet.run('wear', {'items': next.toList()});
                            });
                            return;
                          }
                          if (item.premium) {
                            Navigator.pop(c);
                            if (pet.isPreview) {
                              await previewPurchase(item);
                            } else {
                              await act(() => billing.buy(item.productId));
                            }
                            return;
                          }
                          if (!pet.isPreview &&
                              !pet.expansionEnabled &&
                              PetItem.find(item.id) != null) {
                            await showPetFailure(
                              c,
                              StateError('새 상점 서버 설정을 준비하고 있어요.'),
                            );
                            return;
                          }
                          if (pet.points < item.price) {
                            Navigator.pop(c);
                            await insufficient(item);
                            return;
                          }
                          final yes = await petDialog(
                            c,
                            title: '${item.name}를 살까요?',
                            message: '사고 나면 바로 입혀볼 수 있어요.',
                            rows: [
                              ('가격', '${pointAmount(item.price)}P'),
                              ('지금 포인트', '${pointAmount(pet.points)}P'),
                              (
                                '구매 후 남는 포인트',
                                '${pointAmount(pet.points - item.price)}P',
                              ),
                            ],
                            action: '구매하기',
                            secondary: '취소',
                          );
                          if (!yes || !c.mounted) return;
                          Navigator.pop(c);
                          await act(() async {
                            await pet.run('buy', {
                              'item': item.id,
                              'expected_price': item.price,
                            });
                            if (mounted) {
                              await petDialog(
                                context,
                                title: '옷장에 넣었어요!',
                                message: '내 옷장에서 입힐 수 있어요.',
                              );
                            }
                          });
                        },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('미리보기 취소'),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted) setState(() => preview = Set.of(pet.worn));
  }

  Future<void> insufficient(PetItem item) async {
    final pet = widget.pet;
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
            Text('포인트가 부족해요', style: petText(26)),
            const SizedBox(height: 12),
            Text(
              '${pointAmount(item.price - pet.points)}P를 더 모으면 살 수 있어요.',
              style: petText(18),
            ),
            const SizedBox(height: 16),
            if (pet.adsEnabled && pet.ads < 2)
              PetPrimary(
                '광고 보고 2,000P 받기',
                onTap: () {
                  Navigator.pop(c);
                  act(() async {
                    await PetAdsService.watch(pet);
                  });
                },
              ),
            Text(
              '출석·산책·참여 확인으로 포인트를 모을 수 있어요.',
              style: petText(17, color: PetColors.secondary),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('계속 둘러보기'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> previewPurchase(PetItem item) async {
    final result = await showModalBottomSheet<String>(
      context: petModalContext(context),
      useRootNavigator: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PetPill('결제 미리보기 · 실제 결제 없음'),
            const SizedBox(height: 16),
            Text(item.name, style: petText(26)),
            Image.asset(item.thumbnail, height: 120),
            Text('예시 1,200원 · 영구 소장', style: petText(20)),
            Text(
              '아래 버튼은 결제 상태를 시험해요. Google Play나 실제 지갑에 연결되지 않아요.',
              style: petText(16, color: PetColors.secondary),
            ),
            const SizedBox(height: 16),
            for (final entry in const {
              'success': '테스트 구매 성공',
              'pending': '결제 대기 상태 보기',
              'error': '결제 실패 상태 보기',
              'cancel': '구매 취소',
            }.entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: PetPrimary(
                  entry.value,
                  onTap: () => Navigator.pop(c, entry.key),
                  color: entry.key == 'success'
                      ? PetColors.blue
                      : PetColors.secondary,
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (result == 'success') {
      await widget.pet.run('preview_purchase', {'item': item.id});
      if (!mounted) return;
      await petDialog(
        context,
        title: '테스트 구매 완료',
        message: '미리보기 옷장에 넣었어요. 실제 결제는 발생하지 않았어요.',
      );
    }
    if (!mounted) return;
    if (result == 'pending' || result == 'error' || result == 'cancel') {
      await petDialog(
        context,
        title: result == 'pending'
            ? '결제 대기 중이에요'
            : result == 'error'
            ? '결제를 완료하지 못했어요'
            : '구매를 취소했어요',
        message: result == 'pending'
            ? '실제 결제에서는 구매 확인이 끝난 뒤 아이템을 받아요.'
            : '아이템과 포인트는 변경되지 않았어요.',
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext c) => ListenableBuilder(
    listenable: Listenable.merge([widget.pet, billing]),
    builder: (c, _) {
      final pet = widget.pet;
      final items =
          [...legacy, ...PetItem.all]
              .where(
                (i) =>
                    (section != '내 옷장' || pet.owned.contains(i.id)) &&
                    (source == '전체' || i.source == source) &&
                    (category == '전체' ||
                        (category == '의상'
                            ? i.slot == 'body'
                            : i.slot != 'body')),
              )
              .toList()
            ..sort(
              (a, b) => (a.compatible(pet.species) ? 0 : 1).compareTo(
                b.compatible(pet.species) ? 0 : 1,
              ),
            );
      return PetScreen(
        fullscreen: true,
        colors: const [Color(0xFFF9EFF5), PetColors.background],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PetHeader('옷 입히기', pet: pet),
            PetPhoto(
              pet: pet,
              height: 220,
              outfit: preview,
              live3d: true,
              interactive: true,
            ),
            Row(
              children: [
                for (final label in ['내 옷장', '새 아이템'])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                        label: Text(
                          label,
                          style: petText(
                            17,
                            color: section == label
                                ? Colors.white
                                : PetColors.ink,
                          ),
                        ),
                        selected: section == label,
                        onSelected: (_) => setState(() => section = label),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final label in ['전체', '의상', '장식'])
                  ChoiceChip(
                    label: Text(label),
                    selected: category == label,
                    onSelected: (_) => setState(() => category = label),
                  ),
              ],
            ),
            if (section == '새 아이템')
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final entry in const {
                    '전체': '전체',
                    'points': 'P 아이템',
                    'play': '특별 구매',
                    'activity': '활동 선물',
                  }.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: source == entry.key,
                      onSelected: (_) => setState(() => source = entry.key),
                    ),
                ],
              ),
            if (billing.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: PetCard(
                  child: Text(billing.message!, style: petText(17)),
                ),
              ),
            if (!pet.isPreview && !pet.expansionEnabled)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('새 아이템은 서버 설정 후 구매할 수 있어요.'),
              ),
            if (items.isEmpty)
              PetCard(
                child: Text(
                  '아직 보유한 아이템이 없어요. 새 아이템을 둘러보세요.',
                  style: petText(18),
                ),
              ),
            LayoutBuilder(
              builder: (c, b) {
                final cols =
                    b.maxWidth < 340 ||
                        MediaQuery.textScalerOf(c).scale(1) > 1.2
                    ? 2
                    : 3;
                final width = (b.maxWidth - (cols - 1) * 10) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: width,
                        child: Opacity(
                          opacity: item.compatible(pet.species) ? 1 : .45,
                          child: InkWell(
                            onTap: working ? null : () => choose(item),
                            borderRadius: BorderRadius.circular(20),
                            child: PetCard(
                              padding: 10,
                              child: Column(
                                children: [
                                  if (PetItem.find(item.id) != null)
                                    Image.asset(
                                      item.thumbnail,
                                      cacheWidth: 256,
                                      height: 80,
                                      fit: BoxFit.contain,
                                    )
                                  else
                                    Image.asset(
                                      'assets/pet/items/${item.id}.png',
                                      height: 80,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, e, s) =>
                                          const Icon(Icons.checkroom, size: 60),
                                    ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.name,
                                    textAlign: TextAlign.center,
                                    style: petText(15),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    !item.compatible(pet.species)
                                        ? '다른 동물 전용'
                                        : pet.worn.contains(item.id)
                                        ? '착용 중'
                                        : pet.owned.contains(item.id)
                                        ? '보유'
                                        : pet.stage < item.minStage
                                        ? '성장기부터'
                                        : item.activity
                                        ? '활동 선물'
                                        : item.premium
                                        ? (pet.isPreview
                                              ? '결제 미리보기'
                                              : billing
                                                        .products[item
                                                            .productId]
                                                        ?.price ??
                                                    '판매 준비 중')
                                        : '${pointAmount(item.price)}P',
                                    textAlign: TextAlign.center,
                                    style: petText(
                                      13,
                                      color: item.premium
                                          ? PetColors.purple
                                          : PetColors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            if (pet.worn.isNotEmpty)
              PetPrimary(
                '모두 벗기기',
                light: true,
                onTap: pet.busy
                    ? null
                    : () => act(() async {
                        await pet.run('wear', {'items': <String>[]});
                        setState(() => preview = {});
                      }),
              ),
            TextButton(
              onPressed: billing.available ? () => act(billing.restore) : null,
              child: const Text('구매한 아이템 다시 확인'),
            ),
            Text(
              'P 아이템과 Google Play 구매를 구분해요. 기본 돌봄과 산책은 무료예요.',
              style: petText(15, color: PetColors.muted),
            ),
          ],
        ),
      );
    },
  );
}

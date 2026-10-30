import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'pet_preview_controller.dart';

/// Store callbacks are never proof of ownership. The authenticated backend checks
/// Play's purchase token, product, account binding and purchase state first.
class PetBillingService extends ChangeNotifier {
  PetBillingService(this.pet);
  final PetPreviewController pet;
  final store = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? subscription;
  final products = <String, ProductDetails>{};
  final _verifying = <String>{};
  String? message;
  bool available = false, busy = false, disposed = false;
  Future<void> initialize(Set<String> ids) async {
    if (pet.isPreview ||
        !pet.storeEnabled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    subscription ??= store.purchaseStream.listen(
      _updates,
      onError: (_) {
        message = '구매 상태를 확인하지 못했어요. 다시 확인해주세요.';
        _notify();
      },
    );
    try {
      available = await store.isAvailable();
      if (!available) {
        message = 'Google Play에 연결할 수 없어요.';
        _notify();
        return;
      }
      final response = await store.queryProductDetails(ids);
      products.addAll({for (final p in response.productDetails) p.id: p});
      if (response.error != null) message = '상품 가격을 불러오지 못했어요.';
    } catch (_) {
      message = 'Google Play에 연결하지 못했어요.';
    }
    _notify();
  }

  Future<void> buy(String id) async {
    if (busy) return;
    final product = products[id];
    if (!available || product == null) throw StateError('아직 판매를 준비하고 있어요.');
    busy = true;
    message = 'Google Play에서 구매를 확인해주세요.';
    _notify();
    try {
      final launched = await store.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
          applicationUserName: pet.repository!.client.auth.currentUser!.id,
        ),
      );
      if (!launched) {
        busy = false;
        message = '결제창을 열지 못했어요.';
        _notify();
      }
    } catch (_) {
      busy = false;
      message = '결제를 시작하지 못했어요.';
      _notify();
    }
  }

  Future<void> restore() async {
    if (!available) throw StateError('Google Play 연결을 확인해주세요.');
    message = '구매한 아이템을 다시 확인하고 있어요.';
    _notify();
    await store.restorePurchases(
      applicationUserName: pet.repository!.client.auth.currentUser!.id,
    );
  }

  Future<void> _updates(List<PurchaseDetails> rows) async {
    for (final row in rows) {
      if (row.status == PurchaseStatus.pending) {
        message = '결제 대기 중이에요. 완료되면 아이템을 받아요.';
        busy = false;
        _notify();
        continue;
      }
      if (row.status == PurchaseStatus.canceled ||
          row.status == PurchaseStatus.error) {
        message = row.status == PurchaseStatus.canceled
            ? '결제를 취소했어요.'
            : '결제를 완료하지 못했어요. 다시 시도해주세요.';
        busy = false;
        _notify();
        continue;
      }
      final token = row.verificationData.serverVerificationData;
      if (!_verifying.add(token)) continue;
      try {
        message = '구매를 확인하고 있어요.';
        _notify();
        final response = await pet.repository!.client.functions.invoke(
          'pet-play-purchase',
          body: {'token': token, 'product': row.productID},
        );
        if (response.status != 200 ||
            response.data is! Map ||
            response.data['verified'] != true) {
          throw StateError('구매 확인 중이에요. 잠시 후 구매 복원으로 확인해주세요.');
        }
        await pet.load();
        if (row.pendingCompletePurchase) await store.completePurchase(row);
        message = '구매한 아이템을 옷장에 넣었어요.';
      } catch (e) {
        message = e is StateError
            ? e.message
            : '구매를 확인하지 못했어요. 구매 복원으로 다시 확인해주세요.';
      } finally {
        _verifying.remove(token);
        busy = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!disposed) notifyListeners();
  }

  @override
  void dispose() {
    disposed = true;
    subscription?.cancel();
    super.dispose();
  }
}

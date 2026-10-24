import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'pet_preview_controller.dart';

class PetAdsService {
  static const productionUnit = String.fromEnvironment('PET_REWARDED_AD_UNIT');
  static bool get configured =>
      defaultTargetPlatform == TargetPlatform.android &&
      (kDebugMode || productionUnit.isNotEmpty);
  static Future<PetOutcome> watch(PetPreviewController pet) async {
    if (pet.ads >= 2) throw StateError('오늘 광고 보상을 모두 받았어요. 내일 다시 만나요.');
    if (!configured) throw StateError('광고 계정을 연결하고 있어요. 잠시 후 다시 확인해주세요.');
    final session = await pet.run('ad_session');
    await MobileAds.instance.initialize();
    final loaded = Completer<RewardedAd>();
    RewardedAd.load(
      adUnitId: kDebugMode
          ? 'ca-app-pub-3940256099942544/5224354917'
          : productionUnit,
      request: const AdRequest(nonPersonalizedAds: true),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: loaded.complete,
        onAdFailedToLoad: (e) =>
            loaded.completeError(StateError('광고를 준비하지 못했어요. 잠시 후 다시 시도해주세요.')),
      ),
    );
    final ad = await loaded.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw StateError('광고 준비가 늦어지고 있어요. 다시 시도해주세요.'),
    );
    await ad.setServerSideOptions(
      ServerSideVerificationOptions(customData: '${session.data['session']}'),
    );
    var earned = false;
    final closed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) closed.complete();
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        if (!closed.isCompleted) {
          closed.completeError(StateError('광고를 열지 못했어요. 포인트는 변경되지 않았어요.'));
        }
      },
    );
    ad.show(onUserEarnedReward: (_, _) => earned = true);
    await closed.future;
    if (!earned) throw StateError('광고를 끝까지 보지 않아 보상을 받지 못했어요.');
    // The mobile callback never directly grants points; Google SSV must verify.
    for (var i = 0; i < 12; i++) {
      try {
        return await pet.run('ad_claim', {'session': session.data['session']});
      } on StateError {
        if (i == 11) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError('광고 보상을 확인 중이에요. 잠시 후 다시 확인해주세요.');
  }
}

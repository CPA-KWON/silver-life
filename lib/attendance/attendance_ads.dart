import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceAdOffer {
  const AttendanceAdOffer({
    required this.points,
    required this.remaining,
    this.enabled = false,
  });
  final int points, remaining;
  final bool enabled;
}

enum AttendanceAdResult { completed, cancelled, unavailable, pending }

/// The SDK earned callback alone never credits a wallet. Production claims
/// require the signed Google SSV callback and an authenticated server session.
class AttendanceAds {
  AttendanceAds({this.supabase});
  final SupabaseClient? supabase;
  static const unit = String.fromEnvironment('ATTENDANCE_REWARDED_AD_UNIT');
  static const live = bool.fromEnvironment(
    'ATTENDANCE_ADS_LIVE',
    defaultValue: false,
  );
  bool get testing => !live;
  SupabaseClient get client => supabase ?? Supabase.instance.client;
  Future<AttendanceAdOffer> offer({
    required int streak,
    required bool attended,
  }) async {
    if (testing) {
      return AttendanceAdOffer(
        points: 20,
        remaining: attended ? 2 : 0,
        enabled: attended,
      );
    }
    if (unit.isEmpty || defaultTargetPlatform != TargetPlatform.android) {
      return const AttendanceAdOffer(points: 20, remaining: 0);
    }
    final result = await client
        .rpc('attendance_ad_status')
        .timeout(const Duration(seconds: 8));
    return AttendanceAdOffer(
      points: (result['points'] as num).toInt(),
      remaining: (result['remaining'] as num).toInt(),
      enabled: result['enabled'] == true,
    );
  }

  Future<AttendanceAdResult> watch() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AttendanceAdResult.unavailable;
    }
    if (!testing && unit.isEmpty) return AttendanceAdResult.unavailable;
    String? session;
    if (!testing) {
      final started = await client
          .rpc('attendance_ad_start')
          .timeout(const Duration(seconds: 8));
      session = started['session'] as String;
    }
    try {
      await MobileAds.instance.initialize().timeout(
        const Duration(seconds: 10),
      );
    } catch (_) {
      return AttendanceAdResult.unavailable;
    }
    final loaded = Completer<RewardedAd>();
    var expired = false;
    RewardedAd.load(
      adUnitId: testing ? 'ca-app-pub-3940256099942544/5224354917' : unit,
      request: const AdRequest(nonPersonalizedAds: true),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (expired) {
            ad.dispose();
          } else {
            loaded.complete(ad);
          }
        },
        onAdFailedToLoad: (_) {
          if (!loaded.isCompleted) loaded.completeError(StateError('no-fill'));
        },
      ),
    );
    RewardedAd ad;
    try {
      ad = await loaded.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      expired = true;
      return AttendanceAdResult.unavailable;
    }
    if (session != null) {
      try {
        await ad.setServerSideOptions(
          ServerSideVerificationOptions(customData: session),
        );
      } catch (_) {
        ad.dispose();
        return AttendanceAdResult.unavailable;
      }
    }
    var earned = false;
    final closed = Completer<AttendanceAdResult>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        if (!closed.isCompleted) {
          closed.complete(
            earned
                ? AttendanceAdResult.completed
                : AttendanceAdResult.cancelled,
          );
        }
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        if (!closed.isCompleted) {
          closed.complete(AttendanceAdResult.unavailable);
        }
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (_) {
      ad.dispose();
      return AttendanceAdResult.unavailable;
    }
    final outcome = await closed.future;
    if (outcome != AttendanceAdResult.completed || testing) return outcome;
    for (var attempt = 0; attempt < 8; attempt++) {
      final result = await client
          .rpc('attendance_ad_claim', params: {'p_session': session})
          .timeout(const Duration(seconds: 8));
      if (result['granted'] == true) return AttendanceAdResult.completed;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return AttendanceAdResult.pending;
  }
}

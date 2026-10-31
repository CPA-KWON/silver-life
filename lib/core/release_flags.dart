import 'package:flutter/foundation.dart';

/// 구글 플레이에 올리는 출시 빌드인지. 테스트용 앱에서는 숨긴 기능도 그대로 보여서
/// 계속 개발하고 시험할 수 있다. 테스트에서는 [debugTreatAsReleaseBuild]로 바꾼다.
@visibleForTesting
bool? debugTreatAsReleaseBuild;

bool get isReleaseBuild => debugTreatAsReleaseBuild ?? kReleaseMode;

/// 유료 구매를 켜는 설정값 하나. 첫 출시는 꺼져 있다. 켜려면 빌드 명령에
/// `--dart-define=ENABLE_PAID_ITEMS=true`를 붙인다.
/// (Play Console 상품 등록과 pet-play-purchase 서버 설정도 함께 필요하다.)
const kPaidItemsEnabled = bool.fromEnvironment('ENABLE_PAID_ITEMS');

bool get paidItemsVisible => !isReleaseBuild || kPaidItemsEnabled;

/// 광고 버튼은 운영 광고 단위가 빌드에 들어 있을 때만 보여 준다. 없으면
/// "이용할 수 없어요" 안내 대신 버튼 자체가 없다. 테스트용 빌드는 테스트 광고를 쓴다.
bool rewardedAdVisible(String productionUnit) =>
    !isReleaseBuild || productionUnit.isNotEmpty;

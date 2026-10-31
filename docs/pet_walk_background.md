# 산책 백그라운드 기록 다시 켜는 방법

첫 출시에서는 구글 플레이 심사 부담을 줄이려고 포그라운드 서비스를 뺐다. 지금은 **앱 화면이 켜져 있는 동안만** 걸음 수와 위치를 기록한다(`PetWalkTracker.kt`). 앱을 닫거나 화면을 끄면 기록이 멈추고, 그동안의 걸음은 세지 않는다. 복귀 시간 설정과 복귀 알림도 숨겼다.

## 지금 상태

- 삭제: `PetWalkService.kt`, 권한 `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH`, `FOREGROUND_SERVICE_LOCATION`
- 라이브러리가 넣는 항목도 제거: `androidx.work`의 `FOREGROUND_SERVICE`, `geolocator`의 `GeolocatorLocationService` (`AndroidManifest.xml`의 `tools:node="remove"`)
- 유지: `ACTIVITY_RECOGNITION`(걸음 수), 위치 권한(사용 중일 때만)
- 스위치: `lib/pet/pet_walk_service.dart`의 `kPetWalkBackground = false`. 복귀 시간 설정·지남 안내·알림 권한 요청을 숨긴다.

## 다시 켜기

1. 삭제 직전 파일을 되살린다. 기준 커밋은 `5a68b6a`(main)이다.
   ```bash
   git checkout 5a68b6a -- android/app/src/main/kotlin/com/silverlife/silver_life/PetWalkService.kt android/app/src/main/kotlin/com/silverlife/silver_life/MainActivity.kt
   ```
   `MainActivity.kt`는 되돌린 뒤 그 사이 추가된 변경이 없는지 비교한다. `PetWalkTracker.kt`는 지운다.
2. `android/app/src/main/AndroidManifest.xml`에서 `tools:node="remove"` 줄 2개를 지우고, 아래를 다시 넣는다.
   ```xml
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_HEALTH"/>
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
   <service android:name=".PetWalkService" android:exported="false" android:foregroundServiceType="health|location" />
   ```
3. `kPetWalkBackground`를 `true`로 바꾼다.
4. 개인정보처리방침의 걸음 수·위치 설명을 "화면을 꺼도 기록"에 맞게 고친다.
5. Play Console에서 **앱 콘텐츠 → 포그라운드 서비스 권한** 신고서를 내고, health·location을 왜 쓰는지 보여 주는 시연 영상을 준비한다.
6. 실물 안드로이드 기기에서 화면 꺼짐, 배터리 최적화, 복귀 알림을 확인한다.

# 실버라이프 (Silver Life)

실버세대를 위한 생활 지원 앱 — 주변 시설(병원/약국/경로당/복지관) 찾기, 실버 커뮤니티, 동네모임

- Package: `com.silverlife.app`
- Stack: Flutter(Android) + Supabase(Postgres/Auth/Realtime) + 네이버 지도·지역검색

## 1. 개발 환경 세팅

### Flutter SDK

- 버전: Flutter 3.47.5 (stable) / Dart 3.13.4
- 이 프로젝트는 Windows에서 `C:\Users\user\flutter\bin`에 설치된 SDK로 개발되었습니다. 새 환경에서는 [flutter.dev](https://docs.flutter.dev/get-started/install)에서 SDK를 받아 PATH에 추가하세요.
- Android Studio + Android SDK 필요 (실기기 또는 에뮬레이터 실행용). 이 프로젝트는 지금까지 **실기기(USB 디버깅)로만 테스트**했습니다 — 에뮬레이터는 개발 PC 사양 문제로 사용하지 않았습니다.

```bash
flutter doctor      # 환경 점검, Android toolchain 관련 항목 확인
flutter pub get     # 의존성 설치
```

### 알아둘 것: 의존성/SDK 버전 고정

- `pubspec.yaml`의 `dependency_overrides: permission_handler_android: 13.0.1` — 최신 `permission_handler_android` 14.x가 요구하는 Android SDK 37이 아직 정식 배포되지 않아 고정해둔 것입니다. SDK 37이 정식 출시되면 override를 제거하고 업그레이드하세요.
- `android/app/build.gradle.kts`의 `compileSdk = 36` — 위와 같은 이유로 36에 고정.
- `flutter_naver_map` 플러그인이 Kotlin Gradle Plugin(KGP)을 직접 적용하고 있어, 빌드 시 "Future versions of Flutter will fail to build..." 경고가 뜹니다. 현재는 무시해도 되지만, 플러그인이 Built-in Kotlin을 지원하는 버전을 내면 업그레이드가 필요합니다.

### 실행

```bash
flutter run --dart-define-from-file=.env.json
```

## 2. 환경 변수 (.env.json)

저장소에 커밋되지 않는 파일입니다 (`.gitignore`에 포함). 프로젝트 루트에 아래 형식으로 직접 만들어야 합니다:

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_ANON_KEY": "xxxxxxxx",
  "NAVER_MAP_CLIENT_ID": "xxxxxxxx",
  "NAVER_SEARCH_CLIENT_ID": "xxxxxxxx",
  "NAVER_SEARCH_CLIENT_SECRET": "xxxxxxxx"
}
```

| 키 | 용도 | 발급처 |
|---|---|---|
| `SUPABASE_URL` / `SUPABASE_ANON_KEY` | 백엔드(DB/인증/실시간) | Supabase 프로젝트 대시보드 > Settings > API |
| `NAVER_MAP_CLIENT_ID` | 지도 SDK (`flutter_naver_map`) | [NCP 콘솔](https://console.ncloud.com/maps/application) > Maps > Application 등록 (Android 패키지명 `com.silverlife.app`으로 등록) |
| `NAVER_SEARCH_CLIENT_ID` / `_SECRET` | 지역검색 API (병원/약국/복지관 등 실시간 검색) | [NAVER 개발자센터](https://developers.naver.com/apps) > 애플리케이션 등록 > 검색 API 사용 설정 |

> ⚠️ **네이버 지오코딩(Geocoding) API는 2025년 5월부터 신규 구독이 막혀 있습니다** (NCP 공지 확인됨). 좌표 변환이 필요하면 정식 Geocoding API 대신 **NAVER 지역검색(Local Search) API를 이름 기반으로 활용**하는 방식을 씁니다 (`lib/facility/naver_local_search.dart`, `geocode_via_local_search.py` 참고).

이 키들이 없으면 앱이 "Supabase 설정이 없습니다" 안내 화면만 띄우고 동작하지 않습니다 (`lib/main.dart`).

## 3. Supabase 스키마 세팅

**새 Supabase 프로젝트**라면 SQL Editor에서 아래 순서대로 실행하세요 (각 파일 상단에 실행 순서 주석이 있습니다):

1. `supabase/schema.sql` — `profiles` 테이블, 회원가입 트리거
2. `supabase/community_schema.sql` — `posts`/`comments`, RLS (작성자만 수정·삭제 가능)
3. `supabase/facilities_schema.sql` — `facilities`(장소), `favorites`(즐겨찾기), `checkins`(체크인), `posts`에 모임용 `event_at`/`facility_id` 컬럼 추가
4. `supabase/region_split.sql` — `profiles.region`(단일 문자열)을 `region_sido`/`region_sigungu`로 분리
5. `supabase/facility_region.sql` — `facilities`에도 동일하게 지역 컬럼 추가 + "동네모임 글은 반드시 장소가 있어야 한다" DB 제약조건
6. `supabase/facilities_rls_fix.sql` — `facilities`/`checkins`에 빠져 있던 UPDATE 정책 추가 (없으면 체크인/모임 등록 시 upsert가 RLS 에러로 실패함)
7. `supabase/realtime_setup.sql` — `checkins` 테이블 Realtime 활성화 (체크인 인원수 실시간 반영용)

**기존 프로젝트를 이어받는 경우**는 위 파일들이 이미 실행되어 있을 가능성이 높으니, Table Editor에서 테이블/컬럼이 이미 있는지 먼저 확인 후 없는 것만 실행하세요.

### 경로당 데이터 (선택)

서울시 경로당 2,729곳의 좌표 데이터를 미리 가져와두고 싶다면:
1. `supabase/delete_old_gyeongrodang.sql` (예전 전국 데이터가 이미 들어있다면 먼저 삭제)
2. `supabase/import_gyeongrodang.sql` (서울시 경로당 현황 xlsx를 NAVER 지역검색으로 좌표 매칭한 INSERT문, 3,644건 중 2,729건 매칭)

`import_facilities.sql`은 예전 전국 데이터셋 기준으로 만든 구버전이라 더 이상 쓰지 않습니다. 데이터를 새로 갱신하려면 `geocode_via_local_search.py` / `geocode_and_generate_sql.py`가 xlsx → SQL 생성 파이프라인입니다 (앱 런타임과는 무관한 1회성 스크립트).

## 4. 프로젝트 구조

```
lib/
  main.dart              앱 진입점, Supabase/NaverMap 초기화
  app_theme.dart          브랜드 컬러·테마 (아래 5번 참고)
  auth/                   로그인/회원가입
  home/                   홈 탭, 하단 네비게이션(MainShell)
  facility/                시설찾기 (지도, 검색, 상세, 체크인, 즐겨찾기)
  community/              커뮤니티 게시판, 게시글 상세/댓글
  meetup/                 동네모임 (커뮤니티와 별도 탭, 시설 위치 기반)
  profile/                내 정보 (프로필 수정, 내가 쓴 글 모아보기)
  core/                   여러 화면이 공유하는 것들:
    region_scope.dart       지역 필터 UI(시도/시군구)
    region_picker.dart      지역 선택 드롭다운
    korea_regions.dart      17개 시도/시군구 전체 목록
    address_region.dart     주소 문자열 → (시도, 시군구) 파싱
    meetup_category.dart    동네모임 카테고리 상수 (순환 import 방지용)
    comment_count.dart      댓글 수 조회/배지 위젯 공용 헬퍼
```

멀티플랫폼 폴더(`ios/`, `linux/`, `macos/`, `web/`, `windows/`)는 Android Studio가 자동 생성한 것으로 그대로 두었지만, **배포 대상은 Android(플레이스토어)뿐**입니다.

## 5. 브랜드 컬러 / 테마

`lib/app_theme.dart`에 5개 토큰으로 정의되어 있습니다:

| 토큰 | 값 | 용도 |
|---|---|---|
| `_primary` | `#2563EB` | 버튼, OutlinedButton 테두리/글자, 선택된 칩/포커스 테두리 |
| `_dark` | `#0B1220` | 앱바·하단 탭바 배경, 본문 텍스트 색 |
| `_surface` | `#F5F8FF` | (현재 미사용 — 페이지 배경은 흰색으로 통일됨) |
| `_accent` | `#60A5FA` | `colorScheme.secondary`, 하단 탭바 선택 아이콘 |
| `_highlight` | `#E0EAFF` | 칩/배지 기본 배경, 앱 아이콘 배경 |

**중요:** `_primary`는 흰 글씨를 올려도 대비가 충분(≈5.2:1)하지만, `_accent`/`_highlight`처럼 밝은 색 위에는 항상 진한 잉크색(`_textPrimary` = `_dark`) 텍스트를 써야 합니다 — 실버 사용자 대상 고대비 요구사항 때문입니다. 새 버튼/배지를 추가할 때 이 규칙을 지켜주세요.

앱 아이콘은 `assets/icon/icon.png`(1024×1024, `_highlight` 배경 + `_dark` 색 "S")이며, 수정 후 아래 명령으로 재생성합니다:

```bash
dart run flutter_launcher_icons
```

## 6. 알려진 이슈 / 개발 중 겪은 트러블슈팅

- **NaverMap(PlatformView) + Navigator 전환 충돌**: 지도가 떠 있는 화면 위로 `Navigator.push`로 새 라우트를 띄우면(애니메이션이 0초여도) 렌더 트리가 깨지는 크래시가 반복 발생했습니다. 해결: 시설 상세 화면(`FacilityDetailPage`)을 별도 라우트로 push하지 않고, `FacilitySearchPage`의 `Stack` 안에 `Positioned.fill` 오버레이로 표시하도록 구조를 바꿨습니다 (`lib/facility/facility_search_page.dart`). **지도가 마운트된 화면 위에 새 라우트를 push하는 패턴은 피하세요.**
- **테마의 `Size.fromHeight(56)`(전체 폭 버튼) + `Row`**: 버튼을 `Expanded`/`Flexible` 없이 `Row` 안에 직접 넣으면 "BoxConstraints forces an infinite width" 크래시가 납니다 (`Row`가 non-flex 자식에게 무제한 너비를 주는데, 버튼 테마의 `minWidth: double.infinity`가 그대로 통과되기 때문). `Row` 안에 버튼을 넣을 땐 `style: OutlinedButton.styleFrom(minimumSize: Size(0, 48))`처럼 개별적으로 폭 제약을 풀어주거나 `Flexible`로 감싸세요.
- **Supabase 쿼리 기본 행 개수 제한**: `order()` 없는 쿼리는 서버가 임의 순서로 약 1000행까지만 반환할 수 있어, 거리순 정렬 전에 결과가 잘려 "가까운 곳인데 검색 안 됨" 버그가 났습니다. 위도/경도 바운딩 박스로 먼저 좁힌 뒤 정렬하세요 (`lib/facility/local_facility_search.dart`의 `searchOwnFacilities` 참고).
- **`DateTime.toIso8601String()` 타임존**: `.toUtc()` 없이 바로 직렬화하면 Postgres가 로컬 시각을 UTC로 오인해 9시간이 밀립니다. `event_at`/`checked_in_at` 등 timestamptz 컬럼에 쓸 땐 항상 `.toUtc().toIso8601String()`.
- **`FlutterJNI ... headingStream` 로그 스팸**: 지도의 "내 위치 따라가기" 모드가 켜둔 나침반 센서 리스너가, 핫 리스타트 시 옛 Flutter 엔진이 끊긴 뒤에도 값을 보내려다 나는 경고입니다. 기능상 문제는 없고, 지도 화면에서는 핫 리스타트 대신 완전 재시작을 하면 줄어듭니다.

## 7. 주요 기능 현황

- **인증**: 이메일/비밀번호 가입(닉네임/이름/지역/출생년도), 한글 에러 메시지 번역
- **홈**: 인사말, 다가오는 모임 미리보기, 즐겨찾는 시설, 최근 커뮤니티 글
- **시설찾기**: 네이버 지도, 카테고리(병원/약국/경로당/복지관) + 병원 세부과 필터, "이 위치에서 검색", 경로당은 자체 DB 우선 검색, 상세 화면(체크인·즐겨찾기·전화걸기·여기서 열리는 모임)
- **커뮤니티**: 카테고리별 게시판, 지역 범위 필터(시도/시군구), 글쓰기/수정/삭제(작성자만), 댓글, 댓글 수 표시
- **동네모임**: 시설 위치 기준 지역 필터(글쓴이 아님), 장소 필수 선택, 지난 모임 "완료" 표시, 작성자 수정/삭제
- **내 정보**: 닉네임/지역 수정, 로그아웃, 내가 쓴 모임 글/커뮤니티 글 모아보기

## 8. 자주 쓰는 명령어

```bash
flutter analyze lib test                                    # 정적 분석
flutter test                                                 # 위젯 테스트
flutter run --dart-define-from-file=.env.json                 # 디버그 실행
flutter build appbundle --release --dart-define-from-file=.env.json   # 플레이스토어 업로드용
flutter build apk --release --split-per-abi --dart-define-from-file=.env.json  # 사이드로드/기기 직접 설치용
```

## 9. 플레이스토어 배포 전 남은 작업

- [x] 앱 아이콘 교체
- [ ] 릴리스 서명 키(keystore) 생성 및 `android/key.properties` 설정 (커밋 금지)
- [ ] Play Console 개인정보처리방침 URL 준비 (위치 정보 수집 앱은 필수)
- [ ] 내부 테스트 트랙 업로드 및 실기기 QA

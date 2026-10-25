# 실버라이프 (Silver Life)

내 주변의 시설과 사람을 연결하는 시니어 생활 앱입니다.
Flutter(Android 우선) + Supabase(인증·DB) + 네이버 지도·지역검색을 사용합니다.
Android 앱 ID: `com.silverlife.app`.

## 현재 코드

### 2026-10-25 최신 통합

사용자가 지금까지 개발한 내용을 팀 저장소 main에 반영하도록 승인했습니다.

- 새 홈: 상단 포인트·프로필, 실제 출석 카드/월별 달력, 콩이 카드, 모임·동네 소식·탐색 카드.
- 콩이: 입양·돌봄·의상·3단계 성장·기록, 기존 출석 지갑/경험치 연결, 실제 Supabase 저장 및 좌우 3D 보기.
- Android 산책 기록 서비스와 보상 검증, 보상형 광고 SDK 및 서버 서명 검증 소스.
- 기관 공지: 승인된 기관 담당자의 비공개 저장·수정·게시·중지, 지역 홈/목록/상세 연결.
- 기존 로그인·지도 유지·시설·활동·모임·커뮤니티 기능을 보존했습니다.

현재 운영 프로젝트에는 반려동물·공지 SQL이 적용됐습니다. 다른 서버에 설치할 때는 기존 출석/활동 설정 뒤 `supabase/pet_companion.sql`, `supabase/institution_notices.sql`이 필요합니다.
실제 광고 운영 설정/SSV 배포, 실물 Android의 화면 꺼짐 산책 검증, 준비 중 의상·코스는 후속 작업입니다.
상세 범위는 [이번 main 변경 내용](docs/main_changes_2026_10_25.md), [홈](docs/home_attendance_design.md), [콩이 서버 연결](docs/pet_live_setup.md), [기관 공지](docs/home_local_news.md)를 참고하세요.

사용자가 지정한 main 반영 저장소는 **[CPA-KWON/silver-life](https://github.com/CPA-KWON/silver-life)**입니다.
`fix/integrate-branches-and-security`에서
기존 main의 신고 기능, 지도 안정화 브랜치, 활동 미션·경험 은행 브랜치를 통합했습니다.
충돌 파일의 신고 버튼·지도 유지·시설 위 게시글/편집/장소 선택 화면을 함께 보존했습니다.
운영 서버 반영과 Android 에뮬레이터 검증 결과는 아래 실사용 보완 및 docs/integration_status.md에 정리했습니다.
이전 팀 main 대비 추가 기능과 후속 보완 순서는 [main 변경 비교](docs/main_changes_2026_10_19.md)를 참고하세요.

## 2026-10-18 기능 배치 개편

- 하단 메뉴: 홈 / 시설 찾기 / 활동 / 동네 모임 / 커뮤니티.
- 내 정보·기관 관리는 홈 상단 프로필에서 진입합니다.
- 활동은 맞춤 찾기 / 주간 미션 / 나의 활동 / 경험 나눔의 독립 화면입니다. 가로 탭·좌우 페이지 넘김을 제거했습니다.
- 홈은 실제 신청·미션 요약, 가장 가까운 확정 예정 활동, 추천 최대 2개만 표시합니다.
- 기존 주변 시설은 시설 찾기, 즐겨찾기는 내 정보, 모임·최근 글은 각 전용 메뉴에서 사용합니다.
- 기관 관리의 현황·프로그램·신청자·경험 나눔·성과를 분리했습니다. 기존 API·SQL·RLS는 유지합니다.
- 기능 보존표와 이동 경로는 [IA 개편 안내](docs/ia_restructure.md)를 참고합니다.

## 2026-10-18 목업 디자인 적용

사용자 후속 요청으로 블루 목업을 실제 앱에 적용했습니다. 홈은 블루 그라데이션·실제 미션 원형 현황·흰 요약 영역,
공통 화면은 둥근 카드·블루 버튼과 입력창, 하단은 짙은 둥근 메뉴입니다. 로그인·내 정보도 같은 스타일을 사용합니다.
기존 화면 연결·API·SQL·RLS와 지도 유지 방식은 그대로이며 친구 기능은 추가하지 않았습니다.
본문 18sp·버튼 56dp 이상을 유지하고 320px 화면의 글씨 2배 확대도 확인합니다.
정식 배포·main 병합·GitHub push는 별도 사용자 확인 전 실행하지 않습니다.

## 2026-10-17 실사용 보완

- 검증 대상 Supabase 프로젝트에 활동 테이블·권한·함수와 시설/작성자 연결을 적용했습니다.
- 승인받은 `ins@silverlife.invalid` 계정을 `Silver Life 운영 검증 기관`에 연결했습니다.
- 앱: 홈 상단 내 정보 → 기관 관리. 실제 기관 등록·담당자 연결은 별도 관리자 작업입니다.
- 프로그램 상세 → 지도에서 보기 → 저장된 좌표의 네이버 마커 → 같은 상세 복귀를 지원합니다.
- 기관 신청에 닉네임을 표시합니다. 실명·출생연도는 공개 프로필로 노출하지 않습니다.
- 전체 활동에서 마감·정원 초과를 제외하고, 새 장소 미션은 직전 미션 및 과거 완료 장소에서 100m를 넘는 후보만 선택합니다.
- 로그아웃하면 개인 화면과 화면 이동 이력을 제거하며 Android 뒤로가기를 유지합니다.
- `facility-search` 배포 및 기존 검색키의 서버 Secrets 등록 완료(2026-10-18 사용자 재개·기존 키 사용 승인). 운영 검색 응답 200·시설 5개 확인. 키 값은 앱·Git에 포함하지 않습니다. 과거 공개 이력을 안내한 뒤 사용자가 기존 키 사용을 선택했습니다.
- 승인받은 무료 지도 검증 프로그램 1개는 실제 모집이 아니며 생성 직후 마감했습니다. 실제 운영 프로그램은 기관에서 등록해야 합니다.

새로 설정하거나 다른 프로젝트에 적용할 때는 `python3 tool/prepare_institution_setup.py`로
`supabase/institution_setup.sql`을 생성하고 관리자 검토 후 실행합니다.
기존 데이터는 보존하고, 활동 테이블이 일부만 존재하면 중단합니다.
이미 활동 기능이 있는 서버의 함수만 보완하려면 `supabase/activity_usability_fix.sql`을 사용합니다.
이 설정은 승인된 ins 검증 계정만 연결하므로 다른 담당자에게 무조건 재사용하지 마세요.

## 실행 준비

검증 환경: Flutter 3.47.6 / Dart 3.13.5. Dart 요구 조건은 `^3.13.4`입니다.
Android Studio와 Android SDK 36이 필요합니다.

```bash
flutter pub get
flutter analyze --no-pub lib test
flutter test --no-pub --concurrency=1
```

프로젝트 루트의 `.env.json`에는 공개 가능한 연결 설정만 넣습니다.
이 파일은 git에서 제외됩니다.

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_PUBLIC_ANON_OR_PUBLISHABLE_KEY",
  "NAVER_MAP_CLIENT_ID": "YOUR_MAP_CLIENT_ID"
}
```

```bash
flutter run --dart-define-from-file=.env.json
flutter build apk --debug --dart-define-from-file=.env.json
```

앱의 `.env.json`에는 검색 비밀키나 Supabase 관리자 키를 넣지 마세요.
지도 Client ID는 앱 ID `com.silverlife.app`에 맞춰 등록해야 합니다.
로그인 이메일 인증 복귀 주소는 `com.silverlife.app://login-callback`입니다.
Supabase 설정이 없으면 앱은 설정 안내 화면을 표시합니다.

## 운영 서버 적용 순서

기존 DB를 백업하고 현재 테이블과 권한을 확인한 뒤 적용합니다.
이미 운영 중인 DB에서 최초 생성 SQL을 다시 실행하지 마세요.

1. Supabase 프로젝트 → SQL Editor에서 기존 main 스키마가 적용됐는지 확인합니다.
   필요한 기존 파일: schema.sql → community_schema.sql → facilities_schema.sql →
   region_split.sql → facility_region.sql → facilities_rls_fix.sql →
   realtime_setup.sql → email_exists_function.sql → reports.sql.
2. SQL Editor → New query에서 `supabase/integration_security.sql`을 붙여넣고 Run을 누릅니다.
   이 파일은 트랜잭션 단위이고 다시 실행할 수 있습니다.
3. 활동 기능이 아직 없다면 `supabase/activity_expansion.sql`을 별도 New query에서 적용합니다.
   이 파일은 한 번만 실행합니다. 이미 activity_* 테이블이 있다면 재실행하지 마세요.
4. 아래 설명대로 검색 서버 함수와 새 검색 키를 배포합니다.
4-1. 출석체크·포인트를 쓰려면 `supabase/attendance_points.sql`을 별도 New query에서 실행합니다.
     다시 실행해도 안전합니다. 실행 전에는 앱에 포인트 배지와 출석 팝업이 나타나지 않습니다.
5. 앱을 새 설정으로 빌드하고 일반 회원 2명과 기관 담당자로 기능을 확인합니다.

`integration_security.sql`은 다른 사람의 이름·출생연도를 공개하지 않고
닉네임·시도·시군구만 연결하는 공개 프로필 관계를 추가합니다.
기존 `profiles!inner(...)` 지역 필터는 유지합니다.
시설은 기존 장소를 재사용하며 다른 회원이 덮어쓰지 못하게 합니다.
체크인은 타인의 계정/위치 목록 대신 `facility_presence`의 인원수와 본인 상태만 받습니다.
권한 강화 후 다른 사람의 체크인 이벤트는 직접 전달되지 않으므로,
시설 인원수는 본인 조작·화면 갱신·1분 간격 조회로 갱신됩니다.

## 네이버 검색 비밀키 교체와 서버 배포

이전 커밋에 검색 비밀키가 공개되었습니다. 소스에서 제거했어도 과거 이력에는 남습니다.
발급한 NAVER Cloud API Hub 콘솔에서 해당 키를 폐기하고 새로 발급해야 합니다.
비밀키를 채팅·커밋·앱 파일에 넣지 마세요.

검색은 `supabase/functions/facility-search`에서만 네이버에 요청합니다.
서버는 Supabase Auth로 로그인 토큰을 검증한 뒤 고정된 네이버 주소를 호출합니다.
`verify_jwt=false`는 앱을 공개 허용한다는 뜻이 아닙니다. 함수 내부의 Auth 검사가 필수입니다.

Supabase CLI를 사용할 수 있는 개발 환경에서는:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
# git에 포함되지 않는 supabase/functions/.env 파일에 새 검색 키를 저장한 뒤:
supabase secrets set --env-file supabase/functions/.env
supabase functions deploy facility-search
```

서버의 `supabase/functions/.env`에는 `NAVER_SEARCH_CLIENT_ID`와
`NAVER_SEARCH_CLIENT_SECRET`만 설정합니다. Supabase URL/anon 키는 호스팅 환경에서 제공합니다.
해당 파일은 `.gitignore`에 포함되어 있습니다. 로컬 serve 사용 시에도 두 값을 준비합니다.

### 가까운 순 검색 (카카오 로컬, 2026-10-25)

- 앱은 지도 중심 좌표를 함께 보냅니다. 서버에 `KAKAO_REST_API_KEY` Secret이 있으면 카카오 키워드 검색으로 최대 15개를 받아 옵니다. 병원은 HP8, 약국은 PM9 분류를 씁니다.
  - **카테고리 버튼과 종류 이름 입력**("약국", "근처 치과", "복지관" 등, `nearbyTerm`): 지도 중심 5km 안을 가까운 순으로 검색합니다.
  - **이름 직접 입력**("서울대학교병원" 등): 전국에서 정확도 순으로 검색하고 거리는 표시만 합니다. 지도는 첫 결과로 이동합니다.
- 대시보드 배포는 `handler.ts` 내용과 맨 아래 `Deno.serve(createHandler(...))` 한 줄을 합친 index.ts 한 파일로 합니다. 배포 후 Verify JWT가 OFF인지 꼭 확인합니다(다시 켜지면 입구에서 "Invalid JWT"로 막힘).
- 키가 없거나 카카오가 실패하면(사용량 초과 포함) 기존 네이버 검색으로 자동 대체됩니다.
- 카카오 약관상 결과는 **화면 표시만** 가능하고 저장은 할 수 없습니다(DevTalk 답변 2026-06·08). 그래서 앱은 카카오 결과를 `liveOnly`로 표시하고 캐시하지 않습니다. 즐겨찾기·체크인·모임 장소로 저장할 때는 "시군구 + 이름"으로 네이버를 다시 찾아, 500m 안에서 이름이 같은 네이버 결과만 저장합니다. 맞는 결과가 없으면 저장 기능을 막고 안내 문구를 보여 줍니다.
- 홈 "주변 시설"은 화면 상태로 잠시(메모리) 유지합니다. 기기나 서버에는 저장하지 않습니다.

공공데이터 Python 도구는 같은 이름의 운영체제 환경 변수에서 검색 키를 읽습니다.
앱 설정 파일에서 비밀키를 읽지 않습니다. 키가 없으면 실행을 중단합니다.

## 정식 Android 서명

정식 APK는 팀이 보관하는 하나의 서명 키로 빌드해야 합니다.
`android/key.properties`를 아래 형식으로 준비합니다. 이 파일과 keystore는 git에서 제외됩니다.

```properties
storeFile=/ABSOLUTE/PATH/TO/upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

```bash
flutter build apk --release --split-per-abi --dart-define-from-file=.env.json
flutter build appbundle --release --dart-define-from-file=.env.json
```

서명 설정이 없으면 release 빌드를 중단합니다. 테스트용 debug 서명으로 대신 배포하지 않습니다.
폰용 APK는 arm64-v8a, 블루스택용 APK는 x86_64를 사용합니다.
이전 앱과 서명이 다르면 기존 앱을 삭제해야 설치할 수 있으므로 팀 서명 키를 일관되게 사용하세요.

## 주요 코드 위치

- `lib/main.dart`, `auth/`: 초기화·로그인·회원가입
- `lib/home/`: 홈, 5개 탭, 지도 탭 유지, 주변 시설
- `lib/facility/`: 네이버 지도·검색·시설 상세·즐겨찾기·체크인
- `lib/community/`, `meetup/`: 글·댓글·신고·동네모임
- `lib/activity/`: 활동 추천·미션·경험·기관 운영
- `lib/profile/`: 내 정보·회원정보 수정
- `lib/core/`: 지역·신고·전화·공통 기능
- `lib/app_theme.dart`, `lib/ui/`: v5 보라색 테마·Pretendard·공통 화면 부품
- `supabase/`: DB 설계·권한 보완·서버 검색 함수

동네모임은 posts.category='동네모임'으로 저장하며 facilities의 지역으로 필터링합니다.
커뮤니티는 작성자의 지역으로 필터링합니다. 즐겨찾기는 시설 정보 사본을 저장합니다.
활동 프로그램과 기존 동네모임은 별도 흐름이며 카드 결제·정산은 구현되어 있지 않습니다.

## DB와 서버 자동 검사

운영 DB에 접속하지 않고 임시 PostgreSQL에서 검사합니다.
Node.js 24 이상과 별도 설치한 `@electric-sql/pglite`가 필요합니다.

```bash
PGLITE_MODULE=/ABSOLUTE/PATH/node_modules/@electric-sql/pglite/dist/index.js node test/integration_security_test.mjs
PGLITE_MODULE=/ABSOLUTE/PATH/node_modules/@electric-sql/pglite/dist/index.js node test/activity_database_test.mjs
PGLITE_MODULE=/ABSOLUTE/PATH/node_modules/@electric-sql/pglite/dist/index.js node test/attendance_database_test.mjs
node --test test/facility_search_edge_test.mjs
```

실제 네이버 지도·GPS·운영 DB·이메일 인증·기관 운영 계정은 기기와 서버에서 추가 확인해야 합니다.

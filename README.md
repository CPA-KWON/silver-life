# 실버라이프 (Silver Life)

내 주변의 시설과 사람을 연결하는 시니어 생활 앱입니다.
Flutter(Android 우선) + Supabase(인증·DB) + 네이버 지도·지역검색을 사용합니다.
Android 앱 ID: `com.silverlife.app`.

## 현재 코드

`fix/integrate-branches-and-security`는 기존 main의 신고 기능,
지도 안정화 브랜치, 활동 미션·경험 은행 브랜치를 통합한 작업본입니다.
충돌 파일의 신고 버튼·지도 유지·시설 위 게시글/편집/장소 선택 화면을 함께 보존했습니다.
운영 서버 적용과 실제 기기 검증은 별도 작업입니다.

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
node --test test/facility_search_edge_test.mjs
```

실제 네이버 지도·GPS·운영 DB·이메일 인증·기관 운영 계정은 기기와 서버에서 추가 확인해야 합니다.

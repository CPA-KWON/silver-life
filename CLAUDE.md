# 실버라이프 (Silver Life) — Claude Code 작업 안내서

> 이 파일은 Claude Code가 작업을 시작할 때마다 자동으로 읽는 안내서입니다.
> 프로젝트 폴더 맨 위(pubspec.yaml 파일과 같은 위치)에 두세요.

## 최신 main 반영 승인 (2026-10-25)

- 사용자가 “지금까지 개발한 사항 전체 main에 push”를 명시 승인했다. 대상은 팀 저장소 `CPA-KWON/silver-life`의 `origin/main`.
- `feat/pet-companion-v3`의 반려동물·실제 저장·새 홈·기관 공지·후속 안정화 개발을 모두 포함한다. 아래의 과거 ‘main 병합/push하지 않음’ 기록은 이번 승인 이전의 작업 상태다.
- 비교 기준은 원격 main `2950ae9`. 반영 범위와 남은 운영 설정은 docs/main_changes_2026_10_25.md 참조. 로컬 키·서명 파일·APK는 제외한다.

## 통합 작업 현황 (2026-10-20)

- 현재 기준: `main`. 사용자가 2026-10-19 main push를 명시 승인. `fix/integrate-branches-and-security`의 신고 기능 보존·지도 안정화·활동 기능·IA·블루 디자인을 main으로 fast-forward 통합. 비교 기준과 후속 개선은 docs/main_changes_2026_10_19.md 참조.
- 사용자가 지정한 main 대상은 `CPA-KWON/silver-life` 팀 저장소입니다. 기본 `origin`은 `https://github.com/CPA-KWON/silver-life.git`, `main`은 `origin/main`을 추적합니다. 기존 개인 저장소는 `personal`로 보존하며 별도 지시 없이 업로드하지 않습니다.
- 최신 실행·SQL·검색 서버·서명 안내는 README.md를 기준으로 합니다.
- 검색 비밀키는 앱에서 제거했고 Python 도구는 환경 변수를 사용합니다. 과거 노출 키 교체는 별도입니다.
- 검증 프로젝트 통합 보안/활동 SQL 및 ins 검증 기관 연결 적용 완료. 2026-10-18 사용자가 검색키 작업 보류를 명시 해제하고 기존 키 서버 사용을 승인했습니다. 기존 키를 Supabase Secrets에 등록하고 운영 검색 200·5개 반환 확인. 앱·Git에는 검색키를 넣지 않습니다. 다른 프로젝트는 별도 확인이 필요합니다.
- 2026-10-18 IA 개편: 하단 홈/시설 찾기/활동/동네 모임/커뮤니티. 내 정보·기관 관리는 홈 상단. 활동 4기능 독립 화면과 기관 관리 5목적 분리. docs/ia_restructure.md를 기준으로 합니다.
- 2026-10-18 후속 요청: 기존 블루 목업을 실제 앱의 공통 테마·홈·로그인·내 정보·하단 메뉴에 적용. 친구 기능은 보류. 서버/API/RLS 변경 없이 로컬 확인하며 main 병합·push 전 사용자 확인 유지.
- 공개 프로필 관계로 닉네임·지역만 공유합니다. 개인 profiles 조회는 본인에게만 허용합니다.
- 체크인 조회는 facility_presence, 외부 시설 등록은 ensure_facility를 사용합니다.
- 활동 기본 SQL은 중복 실행용이 아닙니다. 기관 설정은 tool/prepare_institution_setup.py로 만든 institution_setup.sql, 기존 함수 보완은 activity_usability_fix.sql을 검토합니다.
- 2026-10-24 사용자가 운영 Supabase에 attendance_points.sql 실행 완료. 함수·표 생성과 비로그인 차단(42501) 확인. 로그인 상태 출석은 기기에서 확인 필요.

## 콩이 화면 목업 (2026-10-24)

- `feat/pet-companion-v3`에서 사용자 승인한 시뮬레이터용 화면 목업만 추가했습니다. `docs/pet_preview.md`를 먼저 읽으세요.
- 최초 화면 버전은 임시 메모리 데이터였습니다. 현재 실제 저장 연결 상태는 아래 2026-10-25 최신 절을 기준으로 합니다.
- 최초 버전은 4방향 이미지와 아기 GIF였으나, 2026-10-25 사용자의 3D 구현 요청으로 실제 GLB 3단계 모델·자유 회전·Jump/Walk/Eat/Idle을 추가했습니다. 최신 구조는 docs/pet_3d.md 참조. 당시 포인트·서버는 임시 목업이었으며, 최신 연결 현황은 아래 절을 기준으로 합니다.
- 현재 작업의 main 병합·push는 하지 않습니다.

## 콩이 실제 기능 연결 작업 (2026-10-25, 최신)

- 사용자가 화면만 범위를 확대해 ‘실제 기능까지 연결’을 승인. 최신 설명은 `docs/pet_live_setup.md`.
- 원본 UI/분리 레이어 재구성, 실제 RPC 클라이언트, Android 걸음 서비스, Google SSV 검증 소스 추가. 기존 출석 지갑/RLS/지도 유지.
- `supabase/pet_companion.sql`은 2026-10-25 사용자가 SQL Editor에서 실행 성공. 운영 pet_state 200, ins 검증 계정의 실제 입양·출석·먹이/간식 저장 및 별도 재로그인 보존 확인. 실제 지갑 1P/15EXP, 중복 보상·위조 보상·타인 조회·직접 쓰기 차단 확인. 프로그램 완료의 양성 사례와 실물 센서는 별도 검증 필요.
- 광고 운영 ID/SSV 배포·실물 Android 화면 꺼짐 기록 검증은 남음. 실제 지갑과 디자인 미리보기는 분리.
- 레인코트 착용/성체 전용 코스는 사용자에게 자료가 없음을 확인, 준비 중. 겨울 니트 원본도 없어 임시 외형.
- main 병합·push하지 않음.

## 홈·동네 소식 정리 (2026-10-25, 최신)

- 사용자가 오른쪽 수정 목업을 기준으로 홈을 정리하고 기관 공지와 지역 커뮤니티 글을 모두 구분해 표시하도록 요청. 인사/내 정보 → 입양 전후 반려동물 카드 → 다가오는 모임 → 동네 소식. 빈 주간 현황은 숨기고 실제 활동이 있을 때만 아래에 요약한다.
- 원본 이미지/의상으로 카드 구성, 입양 전은 회색 캐릭터. 기존 출석·추천·즐겨찾기 진입과 지도 상태 유지.
- 기관 공지는 승인된 기존 기관 담당자가 비공개 저장 → 확인 후 게시. 기관명/지역/본문/선택 원문 HTTPS 링크/선택 종료일. 외부 공공기관 자동 수집은 구현하지 않았다.
- `supabase/institution_notices.sql` 격리 PostgreSQL 검증 후 사용자가 2026-10-25 SQL Editor 실행 성공. 운영 feed/list API 200 확인. 비공개 공지 1건의 저장·수정·별도 재로그인 보존과 위조 기관·직접 쓰기·비로그인 차단 확인. 기존 표/RLS는 유지. 공개 게시·만료는 격리 DB 검증이며 운영 이용자에게 시험 공지를 게시하지 않았다.
- 기관 공지 경로: 내 정보 → 기관 관리 → 프로그램 관리 → 기관 공지 관리.
- main 병합·push하지 않음. 세부 검증은 docs/home_local_news.md.

## 최신 홈 출석 목업 반영 (2026-10-25)

- 사용자가 새 홈 이미지를 제공하고 디자인 그대로 구현하도록 승인. 날짜/상단 포인트·프로필 → 인사 → 출석 카드 → 콩이 → 모임 → 동네 소식 → 탐색 카드 순서. docs/home_attendance_design.md 참조.
- 출석은 기존 서버 날짜/보상/지갑과 실제 날짜별 기록을 사용. 홈에서 바로 출석하거나 월별 달력을 연다. 콩이 경험치는 기존 RPC로 중복 지급 없이 연결한다.
- 기존 주간 미션·추천 결과·신청·혜택은 전용 화면에 유지. 지도 상태/RLS/보상 SQL 변경 없음. 추가 SQL 필요 없음. main 병합/push하지 않음.

## 1. 우리 팀과 작업 방식 (가장 중요)

- 우리는 경영학과 4학년 5명이고, **전원 코딩을 전혀 모르는 비개발자**입니다.
- 설명은 항상 **쉬운 한국어**로 해주세요. 전문용어를 쓰면 괄호 안에 한 줄로 풀어서 설명해주세요.
- 우리가 직접 해야 하는 일(웹사이트 클릭, 키 발급, 설정 등)은 **"1. ○○ 사이트에 접속 → 2. ○○ 버튼 클릭"처럼 번호를 매겨 순서대로** 알려주세요. 어떤 메뉴를 눌러야 하는지 이름까지 정확히 적어주세요.
- 한 번에 **기능 하나씩만** 작업하세요. 큰 변경 전에는 무엇을 바꿀지 먼저 짧게 설명하고 확인을 받으세요.
- 작업이 끝나면 항상 다음 세 가지를 알려주세요.
  1. 무엇을 바꿨는지 (쉬운 말로 2~3줄)
  2. 우리가 어떻게 확인하면 되는지 (앱에서 어떤 화면 → 어떤 버튼)
  3. 우리가 따로 해야 할 일이 있는지
- 기능 하나가 끝나고 정상 동작이 확인되면 **git으로 저장(커밋)** 해주세요. 문제가 생기면 이전 상태로 되돌릴 수 있어야 합니다.
- 에러가 나면 원인을 쉬운 말로 설명하고 직접 고쳐주세요. 우리가 할 수 있는 건 에러 문구나 화면 캡처를 붙여넣는 것뿐입니다.

## 2. 서비스 소개

- 이름: 실버라이프 (패키지명 `com.silverlife.app`, Dart 패키지명 `silver_life`)
- 한 줄 소개: **내 주변의 시설과 사람을 연결하는 시니어 생활 플랫폼**
- 대상: 50~70대 중장년·시니어. 은퇴 전후로 새 운동·취미를 시작하거나 지역에서 사람을 사귀고 싶은 분
- 핵심 가치: **시설을 찾고 → 활동을 발견하고 → 사람과 연결된다**
- 사용자 흐름: 지역 설정 → 시설 탐색 → 관심 장소 저장 → 정보 공유(커뮤니티) → 오프라인 모임 참여

## 3. 시니어 UI 원칙 (모든 화면에 반드시 적용)

1. **큰 글씨**: 본문 최소 18sp, 제목 22sp 이상. 작은 회색 글씨 금지.
2. **고대비**: 글자와 배경의 명암 대비를 충분히(WCAG AA 4.5:1 이상). 연한 회색 버튼 금지.
3. **큰 버튼**: 누르는 영역은 최소 높이 56dp, 버튼 사이 간격 충분히.
4. **단순한 화면**: 한 화면에 핵심 행동 하나. 아이콘만 있는 버튼 금지 — 아이콘 옆에 반드시 글자를 함께 표시.
5. **쉬운 문구**: "로드 실패" 대신 "불러오지 못했어요. 다시 시도해 주세요"처럼 친절하게.
- 공통 색상·글꼴은 `lib/app_theme.dart`에서 관리합니다. 화면마다 따로 정하지 말고 여기를 사용하세요.

## 4. 기술 구성

- 앱: **Flutter** (안드로이드 우선, 블루스택과 실제 폰에서 테스트)
- 로그인·데이터베이스: **Supabase** (이메일 로그인, Postgres DB)
- 지도: **네이버 지도 SDK** (`flutter_naver_map`)
- 시설 검색: **네이버 API Hub 지역검색** (`naverapihub.apigw.ntruss.com`)
- 기타: geolocator(현재 위치·거리 계산), geocoding(좌표→동네 이름), url_launcher(전화 걸기), permission_handler(위치 권한 요청), http(네이버 검색 요청)
  - shared_preferences는 앱 코드에서 직접 쓰지 않습니다(Supabase가 내부적으로만 사용).
- 키 값들은 `.env.json` 파일에 있고 `--dart-define-from-file=.env.json` 옵션으로 실행·빌드합니다.

### 실행·빌드 명령 (Claude가 직접 실행)
- 실행: `flutter run --dart-define-from-file=.env.json`
- APK 빌드: `flutter build apk --release --split-per-abi --dart-define-from-file=.env.json`
  - 결과물: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (폰용), `app-x86_64-release.apk` (블루스택용)
  - 팀 공유용은 `배포/` 폴더에 `실버라이프_폰용_MMDD.apk`, `실버라이프_블루스택용_MMDD.apk`로 복사 (git 제외됨)
  - 서명이 PC마다 달라서, 다른 PC에서 만든 예전 앱이 깔려 있으면 덮어 설치가 안 됨 → 예전 앱을 지우고 설치
- ⚠️ 이 PC는 Windows 사용자 폴더 이름이 한글이라, 기본 설정으로는 안드로이드 빌드(jni 부품)와 `flutter test`가 실패합니다.
  - 명령 앞에 `PUB_CACHE=C:/src/pub-cache` 를 붙여 실행하세요. 테스트는 `TEMP=C:/src/tmp TMP=C:/src/tmp` 도 함께 붙이세요.
  - 팀이 사용자 환경 변수 `PUB_CACHE=C:\src\pub-cache`를 영구 등록하면 앞의 것은 생략해도 됩니다.

## 5. 폴더 구조 (lib/ 아래)

| 폴더 | 파일 | 내용 |
|---|---|---|
| (맨 위) | `main.dart`, `app_theme.dart` | 앱 시작(Supabase·네이버지도 초기화), 공통 색상·글꼴 |
| `auth/` | `auth_gate`, `login_page`, `signup_page` | 로그인 상태 확인 → 로그인 / 회원가입 화면 |
| `home/` | `main_shell`, `home_tab` | 아래쪽 5개 탭(홈·시설찾기·모임·커뮤니티·내 정보), 홈 화면 |
| `facility/` | `facility_search_page` | 지도 화면 + 시설 상세(즐겨찾기·전화·체크인·여기서 열리는 모임) + 모임 장소 선택 화면 |
| | `naver_local_search` | 네이버 지역검색 요청 (병원·약국·복지관·이름 검색) |
| | `local_facility_search` | 우리 DB(`facilities`)에 미리 넣어둔 시설 검색 — 현재 **경로당만** |
| `community/` | `community_page`, `new_post_page`, `post_detail_page` | 커뮤니티 목록, 글쓰기·수정, 글 상세·댓글 (모임 상세도 이 화면을 같이 씀) |
| `meetup/` | `meetup_page`, `new_meetup_page` | 동네모임 목록(예정/지난), 모임 만들기·수정 |
| `profile/` | `profile_page`, `account_settings_page`, `my_post_list_page`, `privacy_policy_page` | 내 정보 메뉴, 회원정보 수정·로그아웃, 내 글/내 모임 목록, 개인정보처리방침 |
| `core/` | `korea_regions`, `region_picker`, `region_scope`, `address_region`, `comment_count`, `meetup_category`, `report` | 시/도·시/군/구 목록과 선택 상자, "시도 전체/시군구만" 버튼, 주소→지역 변환, 댓글 수 표시, '동네모임' 이름 상수, 신고하기 창 |

lib/ 밖의 중요한 파일
- `supabase/*.sql` — 지금까지 SQL Editor에서 실행한 DB 설계 기록 (아래 6번 참고)
- `import_facilities.py`, `geocode_*.py` — 공공데이터(경로당 등)를 DB에 넣는 SQL을 만드는 일회성 도구 (앱에는 안 들어감)
- `test/widget_test.dart` — 로그인 화면 자동 테스트 1개

## 6. 데이터베이스 (Supabase 테이블)

| 테이블 | 용도 | 칸 (실제 이름) |
|---|---|---|
| `profiles` | 회원 정보 | id(=로그인 계정 id), name, nickname(중복 불가), birth_year, region_sido, region_sigungu, created_at |
| `posts` | 커뮤니티 글 **+ 동네모임** | id, author_id, category, title, content, created_at, event_at, facility_id |
| `comments` | 댓글 | id, post_id, author_id, content, created_at |
| `facilities` | 시설 (공공데이터로 미리 넣은 것 + 사용자가 체크인·모임 장소로 고른 것) | id, name, address, lat, lng, category, telephone, region_sido, region_sigungu, created_at — (name, address) 조합은 중복 불가 |
| `favorites` | 즐겨찾기 | id, user_id, name, address, telephone, lat, lng, category, created_at — ⚠️ `facility_id`가 **없고** 시설 정보를 통째로 복사해 저장 |
| `checkins` | "나 여기 있음" 체크인 | id, user_id, facility_id, checked_in_at — 한 사람당 시설별 1개, 앱에서 3시간 지나면 안 셈 |
| `reports` | 게시글·모임·댓글 신고 | id, reporter_id, post_id 또는 comment_id(둘 중 하나만), reason(욕설·비방/광고/사기 의심/기타), created_at — 같은 사람이 같은 대상 1번만 |
| `point_wallets` | 포인트 지갑 (`attendance_points.sql`) | user_id, balance(보유), total_earned(누적 획득), last_attended_on, current_streak, updated_at |
| `attendance_days` | 날짜별 출석 이력 | user_id, attended_on(한국 날짜), streak, points — 사람·날짜당 1줄 |
| `point_ledger` | 포인트 변동 내역 | id, user_id, amount, reason(현재 attendance만), ref_date — 나중에 다른 보상·사용을 reason으로 확장 |

- `posts.category` 값은 `자유게시판`, `건강정보`, `나눔·도움요청`, `동네모임` 4가지만 허용됩니다(DB에서 막음).
- 동네모임은 별도 테이블이 아니라 `posts`에 `category = '동네모임'`으로 저장되고, `event_at`(모임 일시)과 `facility_id`(모임 장소)를 씁니다. 모임은 장소가 반드시 있어야 합니다(DB 규칙 `meetup_requires_facility`).
- 커뮤니티 글은 **글쓴이의 사는 지역**(`profiles.region_*`)으로, 모임은 **모임 장소의 지역**(`facilities.region_*`)으로 걸러서 보여줍니다.
- 신고 3건 이상인 글·댓글은 DB 읽기 권한(RLS)에서 숨겨집니다(글쓴이 본인에게만 보임). 팀은 대시보드 Table Editor의 `report_summary`(신고 모아보기)에서 확인합니다.
- 기타 DB 기능: `email_exists(check_email)` 함수(회원가입 이메일 중복확인), `handle_new_user` 트리거(가입하면 `profiles` 줄을 자동 생성), `checkins` 실시간 알림(체크인 인원 자동 갱신).
- 출석체크: 앱은 `attendance_status()`·`attendance_check_in()` 함수만 부르고 포인트 표 3개는 읽기만 합니다. 출석일은 서버 시간 기준 한국시간 0시에 바뀌고, 연속 7·14·30일째에 3·5·10포인트(그 외 1포인트)를 줍니다.
- DB 설계 기록은 `supabase/` 폴더의 SQL 파일에 있습니다. 실행 순서: `schema.sql` → `community_schema.sql` → `facilities_schema.sql` → `realtime_setup.sql` → `facilities_rls_fix.sql` → `region_split.sql` → `facility_region.sql` → `email_exists_function.sql` → `reports.sql` → (데이터) `delete_old_gyeongrodang.sql` → `import_gyeongrodang.sql`
- ⚠️ 위 표는 2026-10-14에 코드와 `supabase/*.sql`을 읽고 정리한 것입니다. 대시보드에서 SQL 파일 없이 직접 바꾼 내용이 있다면 실제 DB와 다를 수 있습니다(특히 `profiles` 읽기 권한 — 8번 아래 "점검 메모" 참고).
- DB 구조를 바꿔야 할 때는 Supabase 대시보드 **SQL Editor에 붙여넣을 SQL**을 만들어주고, 붙여넣는 방법을 단계별로 알려주세요. 우리가 실행한 뒤 "완료"라고 하면 이어서 진행하세요.

## 7. 보안 규칙 (절대 지킬 것)

- **비밀키(secret)는 앱 코드나 `.env.json`에 넣지 않습니다.** 앱 파일(APK)은 누구나 열어볼 수 있기 때문입니다.
  - 네이버 지역검색처럼 비밀키가 필요한 요청은 **Supabase Edge Function**(서버)을 거쳐서 보내고, 비밀키는 Supabase의 Secrets에 저장합니다.
  - 앱에 들어가도 되는 것: Supabase URL, Supabase publishable(anon) 키, 네이버 지도 SDK의 Client ID
- `.env.json`, 비밀키가 들어 있는 파일은 git에 올리지 않습니다(`.gitignore`에 포함).
- 모든 테이블은 **RLS(행 수준 보안: 본인 글만 수정·삭제할 수 있게 하는 권한 설정)** 가 켜져 있어야 합니다.
- service_role 키(관리자 키)는 절대 앱에 넣지 않습니다.

## 8. 현재 상태와 할 일

### 완성된 기능
- 회원가입(이메일 중복확인 버튼, 닉네임 중복은 가입 버튼을 누른 뒤에야 알려줌, 이메일 인증, 출생연도, 시/도·시/군/구), 로그인·로그아웃
- 지도 기반 시설 찾기(이름 검색, "이 위치에서 검색", 진료과 분류)
- 시설 상세, 즐겨찾기, 전화 걸기, "여기서 열리는 모임", "나 여기 있음" 체크인
- 지역 커뮤니티(글·수정·삭제·댓글·카테고리)
- 동네모임 만들기·수정, 시설을 모임 장소로 지정, 예정/지난 모임
- 홈(다가오는 모임, 최근 글), 내 정보, 내 글 관리, 개인정보처리방침
- 게시글·모임·댓글 신고하기(사유 4가지, 중복 신고 불가, 3건 이상 숨김)
- 출석체크(하루 1번 출석도장, 연속 출석 보상, 월별 달력)와 포인트 배지(모든 탭 상단 오른쪽 🪙 P)
- 홈에 즐겨찾는 시설 3개, 모임 장소를 즐겨찾기에서 고르기

### 남은 할 일 (우선순위 순)
1. [x] 네이버 지역검색 서버 연결 (사용자 승인한 기존 키를 비공개 서버 설정에 등록 완료)
2. [ ] 모든 테이블 RLS 점검
3. [ ] 동네모임 **참여하기 / 참여 취소 / 참여자 목록 / 최대 인원**
4. [ ] 시연 지역 공공데이터(경로당·복지관·병원·약국)를 `facilities`에 미리 넣기
5. [x] 게시글·모임·댓글 **신고하기** (3건 이상 숨김, 대시보드 `report_summary`에서 확인)
6. [ ] 실제 기기에서 시니어 UI 점검 (공통 글씨·버튼 크기 보완 및 자동 확대 검사 완료)
7. [ ] (여유 있으면) 내 지역·관심 카테고리 기반 모임 먼저 보여주기

작업이 끝날 때마다 위 체크박스를 [x]로 바꿔주세요.

### 점검 메모 (2026-10-14 코드 전체 점검 결과)
- 🔴 네이버 지역검색 비밀키가 `geocode_and_generate_sql.py`, `geocode_via_local_search.py`에 그대로 적혀 **공개 GitHub 저장소에 올라가 있음** → 키 재발급 후 스크립트가 키를 `.env.json`에서 읽도록 바꿔야 함. 앱에도 같은 비밀키가 들어감(할 일 1번).
- `supabase/schema.sql` 기준 `profiles`는 "본인 것만 읽기"라서, 그대로라면 커뮤니티 글쓴이 닉네임이 "알 수 없음"으로 나오고 다른 사람 글이 목록에서 빠짐. → 2026-10-14 에뮬레이터에서 실제로 "알 수 없음"이 나오는 것 확인함. 할 일 2번 때 고칠 것.
- `facilities`는 로그인한 누구나 수정 가능, `checkins`는 누가 어디 있는지(user_id) 누구나 읽기 가능 → RLS 점검 때 정리.

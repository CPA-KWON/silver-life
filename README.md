# 실버라이프 (Silver Life)

실버세대를 위한 생활 지원 앱 — 주변 시설(병원/약국/경로당/복지관) 찾기, 실버 커뮤니티

- Package: `com.silverlife.app`
- Stack: Flutter (Android) + Supabase

## 개발 환경

이 저장소를 클론한 뒤:

```bash
flutter pub get
```

Supabase 프로젝트를 만든 후, URL과 anon key를 `--dart-define`으로 전달하여 실행합니다 (키를 코드에 하드코딩하거나 커밋하지 마세요):

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=xxxxxxxx
```

실제로는 매번 인자를 치는 대신 `.env.json` 파일(git-ignored)을 만들어 아래처럼 실행하세요:

```bash
flutter run --dart-define-from-file=.env.json
```

`.env.json`에 필요한 키:

```json
{
  "SUPABASE_URL": "https://xxxx.supabase.co",
  "SUPABASE_ANON_KEY": "xxxxxxxx",
  "NAVER_MAP_CLIENT_ID": "xxxxxxxx"
}
```

`NAVER_MAP_CLIENT_ID`는 [네이버 클라우드 플랫폼 콘솔](https://console.ncloud.com/maps/application) > Maps > Application 등록에서 발급받습니다 (Android 패키지명 `com.silverlife.app`으로 등록).

## Supabase 스키마

SQL Editor에서 순서대로 실행하세요:
1. `supabase/schema.sql` — 회원 프로필(`profiles`)
2. `supabase/community_schema.sql` — 커뮤니티 게시글/댓글(`posts`, `comments`), 카테고리: 자유게시판/동네모임/건강정보/나눔·도움요청

## 플레이스토어 배포 전 남은 작업

- [ ] 앱 아이콘 교체 (`android/app/src/main/res/mipmap-*/ic_launcher.png`) — [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) 사용 권장
- [ ] 릴리스 서명 키(keystore) 생성 및 `android/key.properties` 설정 (커밋 금지)
- [ ] 시설 데이터 출처 결정 (공공데이터포털 병원정보 API / 네이버 장소검색 API 등)
- [ ] Play Console 개인정보처리방침 URL 준비 (위치 정보 수집 앱은 필수)
- [ ] 앱 번들(`flutter build appbundle`) 빌드 및 내부 테스트 트랙 업로드

## 유용한 명령어

```bash
flutter doctor          # 개발 환경 점검
flutter run             # 디버그 실행
flutter build appbundle # 플레이스토어 업로드용 릴리스 빌드
```

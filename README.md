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

반복 입력이 번거로우면 `--dart-define-from-file=env.json` 형식으로 로컬 JSON 파일을 만들어 사용하세요 (해당 파일은 `.gitignore`에 의해 커밋되지 않습니다).

## 플레이스토어 배포 전 남은 작업

- [ ] 앱 아이콘 교체 (`android/app/src/main/res/mipmap-*/ic_launcher.png`) — [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) 사용 권장
- [ ] 릴리스 서명 키(keystore) 생성 및 `android/key.properties` 설정 (커밋 금지)
- [ ] 지도 SDK 선정 및 연동 (카카오맵/네이버맵/Google Maps 중 국내 장소 검색 정확도 기준으로 결정)
- [ ] Supabase 프로젝트 생성 및 커뮤니티(게시글/댓글) 테이블 + RLS 정책 설계
- [ ] Play Console 개인정보처리방침 URL 준비 (위치 정보 수집 앱은 필수)
- [ ] 앱 번들(`flutter build appbundle`) 빌드 및 내부 테스트 트랙 업로드

## 유용한 명령어

```bash
flutter doctor          # 개발 환경 점검
flutter run             # 디버그 실행
flutter build appbundle # 플레이스토어 업로드용 릴리스 빌드
```

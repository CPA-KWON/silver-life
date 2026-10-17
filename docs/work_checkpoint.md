# 작업 인계 기록

- 날짜: 2026-10-17
- 원본 기준 저장소: hans5040/silver-life
- 사용자 승인 업로드 대상: hangyul0504-droid/silver-life
- 기준: design/ppt-ui-refresh / 7953f5fe207bd0687394cb13bfd163a24398ec5e
- 작업 브랜치: feature/activity-missions-experience-bank
- 사용자 승인에 따라 위 개인 저장소의 작업 브랜치에 업로드한다. 개인 main 병합·팀 main 수정·실제 Supabase 적용은 하지 않는다.

이전 작업 커밋 344fb51은 재개한 실행 환경에서 복구되지 않았다. 기존 v5 파일 위에서 확정 기능과 오류 보완 내역을 재구성했고 새로 검증했다. 이전 통과 수치를 현재 코드의 결과로 사용하지 않는다.

기능 범위·서버 활성화 절차는 activity_features.md, 버튼·오류 보완 및 실환경 제한은 qa_audit.md를 참조한다.

## 완료 상태

로컬 구현·오류 보완·자동 검증을 마쳤다. Flutter 테스트 35개, PostgreSQL 검사 44개 통과 및 정적 분석 지적 없음. 실제 서버·실기기에서 남은 검증은 qa_audit.md에 구분했다. 재개 시 이전 테스트 실패나 미완료 검증 기록 대신 이 기록을 기준으로 한다.

## 다른 Codex 환경에서 이어가기

개인 저장소의 feature/activity-missions-experience-bank 브랜치를 선택한다. main에는 이번 작업을 병합하지 않는다. ZIP·Git bundle로도 동일한 작업 파일을 전달할 수 있다.

```bash
# bundle 파일을 로컬로 내려받은 뒤 실행
git clone silver-life-work.bundle silver-life
cd silver-life
git switch feature/activity-missions-experience-bank
git log -1 --oneline
```

이미 원본 clone이 있는 경우 변경이 없는 작업 폴더에서 다음처럼 bundle의 작업 브랜치를 가져올 수 있다. 같은 이름의 브랜치가 이미 있다면 덮어쓰지 말고 커밋부터 비교한다.

```bash
git fetch /absolute/path/silver-life-work.bundle feature/activity-missions-experience-bank:feature/activity-missions-experience-bank
git switch feature/activity-missions-experience-bank
```

Codex에 전달할 지시:

> docs/work_checkpoint.md, docs/activity_features.md, docs/qa_audit.md를 읽고 현재 작업 브랜치의 상태부터 확인해줘. v5 디자인과 기존 Supabase·네이버 지도·로그인·위치 추적·게시글·모임 CRUD를 유지해줘. 새 기능은 추가 SQL이 아직 실제 서버에 적용되지 않은 상태야. 실제 기기·서버에서 검증되지 않은 항목을 확인하되, 원본 팀 main을 수정하거나 승인 없이 push·merge·실제 DB 변경하지 마. 팀 신규 커밋은 아직 선택 반영하지 않았으니 임의로 병합하지 마. 기존 작업과 충돌하면 알려줘.

5시간 사용량 잔여율은 이 작업 환경에서 직접 조회할 수 없다. 3% 이하라는 정보를 사용자가 전달하면 즉시 저장하고 중단한다.

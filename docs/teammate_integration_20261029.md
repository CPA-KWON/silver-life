# 팀원 main 전체 통합 — 2026-10-29

사용자가 겹치는 기능만이 아니라 최신 main 전체 변경을 지금 한 번에 통합하도록 요청했다.

- 현재 브랜치 feat/activity-hub-mockup, 로컬 작업 보존 커밋 190bd1b.
- 원격 main 44d74f2 전체를 merge. f0aa24c(회원 탈퇴), 44d74f2(모임 참여) 코드·SQL·문서·테스트 모두 포함.
- 충돌 3개: post_detail_page, new_meetup_page, profile_page. 신규 목업을 보존하면서 팀원의 참여 기능/참여한 모임 진입을 연결했다.
- 참여 이력은 팀원의 meetup_participants, 정원은 max_participants(2~30), meetup_join/leave/participation/my_meetups를 기준으로 통일했다. 신규 neighborhood RPC 미적용 상태에서도 팀원 RPC에 연결하는 호환 경로를 제공한다. 두 참여자 표를 따로 쓰지 않는다.
- 탈퇴는 팀원의 delete_my_account() 한 함수로 통일하고, created_by FK의 ON DELETE SET NULL 보완 SQL/안내 문서를 보존했다. 사진 bucket 적용 후에는 본인 사진 정리/본인 재확인 화면도 사용한다.
- home_tab, privacy_policy, account-deletion.html, my_meetups_page 및 기관 승인·포인트 데이터 보존.
- 통합 검증: 팀원 참여/취소/정원/모임장 및 홈 테스트 9개 통과, flutter analyze 지적 없음, 격리 PostgreSQL에서 canonical 참여자 표와 신규 권한 규칙 연결 통과.
- 이전 목업 작업 전체의 회귀 검사/서버 추가 SQL 적용/잔여 디자인 반영은 별도 진행 중. 통합 검사 통과를 전체 작업 완료로 표시하지 않는다.
- main 자체 변경 또는 원격 push 하지 않았다.

## 추가 디자인 요청과 캡처

현재 추가 목업에 없는 '참여한 모임' 예정/지난/빈 상태와 내 정보 메뉴, 인증번호 입력 시트, 기관 담당자 인증 요청, 사진 선택/실패 상태를 사용자에게 요청했다.
실제 캡처는 outputs/designer-current-20261029 및 outputs/SilverLife_추가목업요청_현재화면_20261029.zip에 있다. 테스트 계정 참여 이력이 없어 실제 빈 상태를 촬영했다. 예시 모임 참여나 포인트 변경은 하지 않았다.

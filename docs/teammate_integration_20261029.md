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


## 3차 목업 반영 checkpoint (2026-10-29, 작업 계속 중)

- 추가목업_3차의 참여한 모임 J, 회원정보/휴대폰 V, 글쓰기 사진 W, 기관 인증 O 주요 화면 및 실제 저장 코드를 연결했다. 전체 화면 검증 완료를 뜻하지 않는다.
- 정원 찬 모임 참여자의 취소 차단, 화면 복귀/다시 시도에서 Future를 반환하던 setState 오류, 기관 임시 저장 SQL 이름 충돌, 경험 나눔 등록 시 참여비 노출을 수정했다.
- 활동 첫 화면 전체 프로그램 바로가기, 나의 활동/내 정보의 관심 프로그램 목록, 기관 관리 경험 나눔 바로가기를 추가. 전화·방문 프로그램은 실제 접수 안내를 제공하고 앱 신청/기관 보상으로 간주하지 않는다.
- 현재 코드 전체 Flutter 테스트 155개 통과. 정적 분석 지적 없음. Android debug 빌드/기존 데이터 보존 설치 확인. tool/test_neighborhood_schema.mjs에서 canonical 모임 이력, 비공개 사진/재직 자료, 인증 요청 재시도/타인 차단/본인 승인 금지, 운영자 승인, 프로그램 임시 저장/발행/정원/권한/전화 신청 차단/일괄 처리 원자성을 격리 검증.
- neighborhood_mockups.sql, neighborhood_media.sql, meetup_history.sql, institution_access_requests.sql은 운영 미적용. 기존 Supabase 문자 인증은 비활성인 것을 설정 읽기로 확인. 실제 SMS 발송에는 별도 발송 서비스 설정 필요, 사용자에게 계정 보유 여부 질문 중. 비밀키 출력/커밋 없음.
- 남은 작업: 시설/공지 목업 정리, 운영 SQL 적용과 Android 전체 시나리오/시각 비교, 실물 걸음 센서/운영 광고 등 외부 설정 한계 구분. 사용자가 전체 구현 후 큰 문제 없으면 CPA-KWON/silver-life main push를 승인했으며 아직 push하지 않았다.

## 시설·공지 후속 검증 및 운영 반영

- 2026-10-29 시설/공지/즐겨찾기 목업과 연결 보완 완료. 최신 검증은 docs/mockup_release_20261029.md를 따른다.
- 추가 SQL 전체를 운영 SQL Editor에서 한 트랜잭션으로 적용하고 새 RPC/권한/RLS/비공개 bucket을 확인했다. 위 checkpoint의 미적용 표시는 당시 기록이다.
- 사용자가 문자 발송 서비스 계정이 없다고 답했다. 실제 문자 인증은 준비 중으로 유지하며 설정 절차를 문서화했다.
- 전체 Flutter 테스트 163개 및 정적 검사/Android 빌드 통과. main push 직전 화면/동선 최종 확인 중.

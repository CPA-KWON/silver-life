import 'package:flutter/material.dart';

/// Draft privacy policy text — reviewed for accuracy against what the app
/// actually collects/stores, but not a substitute for legal review before
/// the Play Store submission (see README "배포 전 남은 작업").
const _lastUpdated = '2026-09-21';

const _sections = <(String, String)>[
  (
    '1. 수집하는 개인정보 항목',
    '회원가입 시 이메일, 비밀번호, 이름, 닉네임, 출생년도, 거주 지역(시/도, 시/군/구)을 '
        '수집합니다. 서비스 이용 과정에서 작성하신 게시글·댓글 내용, 즐겨찾기한 시설 정보가 '
        '함께 저장됩니다.',
  ),
  (
    '2. 개인정보의 수집 및 이용 목적',
    '회원 식별 및 로그인, 지역 기반 커뮤니티·동네모임 게시글 노출, 문의 응대, 서비스 부정 '
        '이용 방지를 위해 이용합니다. 출생년도는 실버세대 대상 서비스 제공 확인 목적으로만 '
        '사용하며, 별도 동의 없이 광고 등 다른 목적으로 이용하지 않습니다.',
  ),
  (
    '3. 개인정보의 보유 및 이용 기간',
    '회원 탈퇴 시 지체 없이 파기합니다. 다만 관계 법령에 따라 보존이 필요한 경우 해당 '
        '법령에서 정한 기간 동안 보관합니다.',
  ),
  (
    '4. 위치정보의 처리',
    '주변 시설 찾기 기능 이용 시 기기의 위치 권한 동의를 받아 GPS 좌표를 일회성으로 '
        '조회하며, 서버에 저장하지 않습니다. "나 여기 있음" 체크인 기능은 어느 시설에 '
        '체크인했는지와 시각만 저장하고, 이용자의 실시간 위치 좌표는 저장하지 않습니다.',
  ),
  (
    '5. 개인정보 처리위탁',
    '안정적인 서비스 제공을 위해 아래와 같이 업무를 위탁하고 있습니다.\n'
        '· Supabase (데이터베이스·인증·실시간 서버 운영)\n'
        '· 네이버 클라우드 플랫폼 (지도 표시, 주변 시설 검색)',
  ),
  (
    '6. 개인정보의 제3자 제공',
    '이용자의 동의 없이 개인정보를 외부에 제공하지 않습니다. 다만 법령에 근거가 있거나 '
        '수사기관이 법령에 정한 절차와 방법에 따라 요구하는 경우는 예외로 합니다.',
  ),
  (
    '7. 이용자의 권리와 행사 방법',
    '이용자는 [내 정보 > 회원정보 관리]에서 언제든지 본인의 개인정보를 열람·수정할 수 '
        '있으며, 로그아웃 및 회원 탈퇴(문의처를 통한 요청)를 통해 개인정보 삭제를 요청할 '
        '수 있습니다.',
  ),
  (
    '8. 개인정보의 안전성 확보 조치',
    '비밀번호는 암호화하여 저장하며, 데이터베이스 접근 권한을 최소한의 인원으로 '
        '제한합니다. 각 이용자는 본인이 작성한 정보에만 접근·수정·삭제할 수 있도록 '
        '접근 권한을 설정하고 있습니다.',
  ),
  (
    '9. 문의처',
    '개인정보 관련 문의사항은 앱 내 고객센터 또는 아래 이메일로 연락해주시기 바랍니다.\n'
        '이메일: k808500@naver.com',
  ),
];

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보 처리방침')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('시행일: $_lastUpdated', style: textTheme.bodyMedium),
          const SizedBox(height: 16),
          Text(
            '실버라이프(이하 "앱")는 이용자의 개인정보를 소중히 여기며, 「개인정보 보호법」 '
            '등 관련 법령을 준수합니다. 본 방침은 앱이 어떤 개인정보를 수집하고 어떻게 '
            '이용·보호하는지 안내합니다.',
            style: textTheme.bodyLarge,
          ),
          for (final (title, body) in _sections) ...[
            const SizedBox(height: 24),
            Text(title, style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body, style: textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

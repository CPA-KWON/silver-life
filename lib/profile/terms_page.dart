import 'package:flutter/material.dart';

import '../ui/design_widgets.dart';

/// 약관을 바꾸면 이 값을 올린다. 다음 글쓰기 때 모두에게 다시 동의를 받는다.
/// Draft text — needs legal review before the Play Store submission.
const kTermsVersion = '2026-10-31';

const _sections = <(String, String)>[
  (
    '제1조 (서비스)',
    '실버라이프는 내 주변의 시설을 찾고, 활동과 동네 모임에 참여하며, 이웃과 소통하는 서비스입니다. '
        '앱에 표시되는 시설·프로그램 정보는 공공자료와 기관이 제공한 내용으로, 실제와 다를 수 있으니 '
        '방문 전에 해당 기관에 확인해 주세요.',
  ),
  (
    '제2조 (가입과 탈퇴)',
    '이용자는 본인의 정보로 가입해야 합니다. 언제든지 [내 정보 > 회원정보 관리 > 회원 탈퇴]에서 '
        '탈퇴할 수 있으며, 탈퇴하면 작성한 글·댓글·모임, 포인트, 반려동물 정보가 삭제되고 되돌릴 수 없습니다.',
  ),
  (
    '제3조 (금지되는 행동)',
    '다음과 같은 글, 댓글, 사진, 모임, 닉네임을 올리거나 행동을 해서는 안 됩니다.\n'
        '· 욕설, 비방, 혐오, 괴롭힘\n'
        '· 광고, 홍보, 영업, 다단계 권유\n'
        '· 사기, 금전 요구, 투자 권유 등 다른 사람을 속이는 행동\n'
        '· 음란물, 성적으로 불쾌감을 주는 내용\n'
        '· 전화번호, 주소, 얼굴 사진 등 다른 사람의 개인정보를 동의 없이 공개하는 행동\n'
        '· 법령에 어긋나거나 다른 사람의 권리를 침해하는 내용',
  ),
  (
    '제4조 (위반 시 조치)',
    '이용자는 글, 댓글, 모임, 사용자를 신고할 수 있습니다. 금지되는 내용은 사전 안내 없이 숨겨지거나 '
        '삭제될 수 있고, 신고가 3건 이상 쌓인 글과 댓글은 자동으로 숨겨집니다. 위반 정도에 따라 글쓰기 제한, '
        '이용 정지, 강제 탈퇴 등 이용을 제한할 수 있습니다. 조치에 이의가 있으면 아래 문의처로 알려 주세요.',
  ),
  (
    '제5조 (동네 모임)',
    '모임은 이용자들이 직접 만들고 운영합니다. 낯선 사람과 처음 만날 때는 사람이 많은 공공장소를 이용하고, '
        '돈을 빌려주거나 개인정보를 알려 주지 마세요. 회사는 이용자 사이의 만남이나 거래에 직접 관여하지 않습니다.',
  ),
  (
    '제6조 (포인트)',
    '포인트는 앱 안에서만 쓸 수 있으며 현금으로 바꾸거나 다른 사람에게 넘겨줄 수 없습니다. 부정한 방법으로 '
        '얻은 포인트는 회수할 수 있습니다. 포인트로 보낸 꽃과 구매한 아이템은 돌려받을 수 없습니다.',
  ),
  (
    '제7조 (유료 아이템과 환불)',
    '유료 아이템을 판매하는 경우 결제는 Google Play를 통해 이루어집니다. 구매 후 7일 이내이고 사용하지 않은 '
        '아이템은 환불을 요청할 수 있습니다. 이미 사용했거나 받은 즉시 효과가 적용되는 아이템은 구매 전에 그 사실을 '
        '안내한 경우 환불이 제한될 수 있습니다. 결제 오류나 아이템을 받지 못한 경우에는 환불하거나 다시 지급합니다. '
        '환불은 Google Play 환불 절차 또는 아래 문의처로 요청할 수 있으며, 환불되면 해당 아이템은 회수됩니다. '
        '이 조항은 관련 법령에서 정한 이용자의 권리를 제한하지 않습니다.',
  ),
  (
    '제8조 (서비스 변경)',
    '서비스 내용은 바뀌거나 중단될 수 있습니다. 약관이 바뀌면 앱에서 알리고, 필요한 경우 다시 동의를 받습니다.',
  ),
  ('제9조 (문의)', '이메일: k808500@naver.com'),
];

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bodyStyle = textTheme.bodyLarge?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 1.6,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('이용약관')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SectionCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('시행일: $kTermsVersion', style: bodyStyle),
                for (final (title, body) in _sections) ...[
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(body, style: bodyStyle),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

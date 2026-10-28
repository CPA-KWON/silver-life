/// Shared with community/home/post_detail so none of them need to import
/// meetup_page.dart directly (avoids an import cycle with post_detail_page,
/// which meetup_page.dart itself imports).
const kMeetupCategory = '동네모임';

/// 모임 최대 인원 범위 (DB 규칙 posts_max_participants_range와 같게 유지).
const kMinParticipants = 2;
const kMaxParticipants = 30;
const kDefaultMaxParticipants = 10;

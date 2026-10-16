/// Korean relative time ("방금 전", "3시간 전", "어제", "10월 3일").
/// [time] is a local time; [now] is injectable for tests.
String timeAgo(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final diff = current.difference(time);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inHours < 1) return '${diff.inMinutes}분 전';
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(time.year, time.month, time.day);
  final dayDiff = today.difference(day).inDays;
  if (dayDiff <= 0) return '${diff.inHours}시간 전';
  if (dayDiff == 1) return '어제';
  if (dayDiff < 7) return '$dayDiff일 전';
  if (time.year == current.year) return '${time.month}월 ${time.day}일';
  return '${time.year}.${time.month}.${time.day}';
}

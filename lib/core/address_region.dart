/// Korean addresses always start with "{시도} {시군구} ...", so the first
/// two space-separated tokens give the region without needing a lookup —
/// used when upserting a `facilities` row so meetups can be filtered by
/// where they actually are.
(String, String) parseRegionFromAddress(String address) {
  final parts = address.trim().split(RegExp(r'\s+'));
  final sido = parts.isNotEmpty ? parts[0] : '';
  final sigungu = parts.length > 1 ? parts[1] : '';
  return (sido, sigungu);
}

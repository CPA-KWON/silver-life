/// Public-source dates use the Korean calendar. Keep unknown legacy schedules,
/// but exclude explicitly closed or expired offers from discovery.
bool welfareProgramVisible(Map<String, dynamic> raw, {DateTime? now}) {
  final today = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 9));
  final day =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  if (['closed', 'cancelled'].contains(raw['source_status'])) return false;
  for (final key in ['registration_ends_on', 'program_ends_on']) {
    final value = raw[key];
    if (value is String &&
        RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
        value.compareTo(day) < 0) {
      return false;
    }
  }
  final start = raw['registration_starts_on'];
  return start is! String || start.compareTo(day) <= 0;
}

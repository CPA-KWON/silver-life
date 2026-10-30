/// One existing server/accounting unit represents 100 displayed P. Keep this
/// conversion at the presentation boundary so historical wallets, idempotency
/// keys, item purchasing power and older clients cannot be multiplied twice.
/// EXP, KRW fees, steps and counts must never use this formatter.
const pointsPerAccountingUnit = 100;
String pointAmount(num? accountingUnits) {
  if (accountingUnits == null) return '—';
  final value = (accountingUnits * pointsPerAccountingUnit).round();
  return value.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
}

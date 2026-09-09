import 'money.dart';

/// Indian-style grouping: ₹12,34,567.89 (last 3 digits, then groups of 2).
///
/// Takes **paise**, not rupees. Paise are shown whenever they're non-zero —
/// hiding them used to make a ₹9,737.39 EMI read as "₹9,737", which then
/// didn't reconcile against the bank statement.
String formatMoney(int paise, String currency, {bool alwaysShowPaise = false}) {
  final sign = paise < 0 ? '-' : '';
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final remainder = abs.remainder(100);

  final grouped = _groupIndian(rupees.toString());
  if (remainder == 0 && !alwaysShowPaise) return '$sign$currency$grouped';
  return '$sign$currency$grouped.${remainder.toString().padLeft(2, '0')}';
}

/// Compact form for tight spaces: ₹1.2L, ₹45.3K, ₹950.
String formatMoneyCompact(int paise, String currency) {
  final sign = paise < 0 ? '-' : '';
  final rupees = paise.abs() / 100;
  if (rupees >= 10000000) {
    return '$sign$currency${(rupees / 10000000).toStringAsFixed(1)}Cr';
  }
  if (rupees >= 100000) {
    return '$sign$currency${(rupees / 100000).toStringAsFixed(1)}L';
  }
  if (rupees >= 1000) {
    return '$sign$currency${(rupees / 1000).toStringAsFixed(1)}K';
  }
  return formatMoney(paise, currency);
}

String _groupIndian(String s) {
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Convenience for the handful of places still holding rupees (parsed user
/// input on its way to storage, chart axis labels derived from ratios).
String formatRupees(double rupees, String currency) =>
    formatMoney(rupeesToPaise(rupees), currency);

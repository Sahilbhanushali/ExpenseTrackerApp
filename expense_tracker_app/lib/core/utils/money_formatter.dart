/// Port of expense_bot/bot.py's fmt_money() — Indian-style grouping:
/// ₹12,34,567 (last 3 digits, then groups of 2).
String formatMoney(double amount, String currency) {
  final rounded = amount.round();
  final sign = rounded < 0 ? '-' : '';
  final s = rounded.abs().toString();

  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '$sign$currency$grouped';
}

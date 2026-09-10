import 'expense_parser.dart';
import 'money.dart';

/// Best-effort parse of OCR'd receipt text into the same shape
/// parseMessage() returns. Always an expense, dated today — OCR text has no
/// notion of income vs. expense or a reliable stated date.
class ParsedReceipt {
  /// In paise.
  final int? amountPaise;
  final String category;
  final String note;

  const ParsedReceipt({
    required this.amountPaise,
    required this.category,
    required this.note,
  });
}

/// The line that states what was actually paid. "Grand total", "amount
/// payable", "to pay" and a bare "total" all qualify.
final _totalLineRe = RegExp(
  r'\b(grand\s*total|net\s*(?:total|payable|amount)|amount\s*(?:payable|due)?|'
  r'total|to\s*pay|payable|bill\s*amount)\b',
  caseSensitive: false,
);

/// Lines that look like a total but are not the one to charge: running
/// subtotals and tax rows. "Item Total 175.00" sitting above "TOTAL 190.00"
/// is why a grocery slip used to log the pre-delivery figure.
final _notTheTotalRe = RegExp(
  r'\b(sub[\s-]?total|item\s*total|cart\s*total|gross|taxable|'
  r'cgst|sgst|igst|gst|vat|tax|discount|savings|mrp|round\s*off)\b',
  caseSensitive: false,
);

/// Reference numbers, not money. A UPI transaction id read as an amount
/// logged a ₹6,19,05,72,60,304 lunch.
final _identifierLineRe = RegExp(
  r'\b(txn|transaction|ref(?:erence)?|utr|rrn|invoice|bill\s*no|order\s*(?:id|no)|'
  r'gstin|tin|fssai|receipt\s*no|auth|approval|terminal|batch|'
  r'card|a\/c|account|phone|mobile|tel|pin\s*code)\b',
  caseSensitive: false,
);

/// Money on a receipt: an optional currency marker, digits with optional
/// grouping, optional paise. Deliberately no k/L/cr shorthand — on a fuel
/// bill "9.57 L" is litres, and reading it as 9.57 lakh turned a ₹1,000
/// fill-up into ₹9,57,000.
final _receiptAmountRe = RegExp(
  r'(?<cur>(?:rs\.?|inr|₹)\s*)?'
  // The grouped form must actually contain a comma, otherwise it matches a
  // prefix and stops: "1000.00" came out as 100.
  r'(?<num>\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)(?!\d)',
  caseSensitive: false,
);

/// A run of digits long enough to be an id rather than a price.
final _longDigitRunRe = RegExp(r'\d{7,}');

/// "To Cp Shah And Sons", "Paid to Blinkit" — the payee on a payment
/// screenshot, which is a better note than the first line of the image.
final _payeeRe = RegExp(
  r'^(?:paid\s+to|to|payee|merchant)\s*:?\s+(.{2,40})$',
  caseSensitive: false,
);

class _Candidate {
  final double value;
  final bool hasCurrency;
  const _Candidate(this.value, this.hasCurrency);
}

List<_Candidate> _amountsIn(String line) {
  if (_longDigitRunRe.hasMatch(line.replaceAll(',', ''))) return const [];
  final out = <_Candidate>[];
  for (final m in _receiptAmountRe.allMatches(line)) {
    final raw = m.namedGroup('num');
    if (raw == null) continue;
    final value = double.tryParse(raw.replaceAll(',', ''));
    if (value == null || value <= 0) continue;
    out.add(_Candidate(value, (m.namedGroup('cur') ?? '').isNotEmpty));
  }
  return out;
}

ParsedReceipt parseReceiptText(
  String text, {
  Map<String, List<String>>? extraCategories,
}) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final usable = lines
      .where((l) => !_identifierLineRe.hasMatch(l))
      .toList(growable: false);

  double? amount;

  // 1. The stated total, taking the last one — "grand total" comes after
  //    "sub total", and the final figure is the one actually charged.
  for (final line in usable) {
    if (_totalLineRe.hasMatch(line) && !_notTheTotalRe.hasMatch(line)) {
      final found = _amountsIn(line);
      if (found.isNotEmpty) amount = found.last.value;
    }
  }

  // 2. Otherwise the largest amount that carries a currency marker — on a
  //    payment screenshot that is the "₹560" headline.
  if (amount == null) {
    final marked = [
      for (final line in usable)
        ...(_amountsIn(line).where((c) => c.hasCurrency)),
    ];
    if (marked.isNotEmpty) {
      amount = marked.map((c) => c.value).reduce((a, b) => a > b ? a : b);
    }
  }

  // 3. Last resort: the largest plain number left.
  if (amount == null) {
    final all = [for (final line in usable) ..._amountsIn(line)];
    if (all.isNotEmpty) {
      amount = all.map((c) => c.value).reduce((a, b) => a > b ? a : b);
    }
  }

  final category = detectCategory(
    lines.join('\n').toLowerCase(),
    extraCategories,
  );

  return ParsedReceipt(
    amountPaise: amount == null ? null : rupeesToPaise(amount),
    category: category,
    note: _noteFor(lines),
  );
}

/// Prefers an explicit payee line, then the first line that reads like a
/// name rather than a price or a status word.
String _noteFor(List<String> lines) {
  for (final line in lines) {
    final payee = _payeeRe.firstMatch(line)?.group(1)?.trim();
    if (payee != null && payee.isNotEmpty) return _clip(payee);
  }
  for (final line in lines) {
    final hasLetters = RegExp(r'[A-Za-z]{3,}').hasMatch(line);
    final isStatus = RegExp(
      r'^(paid|success(?:ful)?|completed|debited|credited)\b',
      caseSensitive: false,
    ).hasMatch(line);
    if (hasLetters && !isStatus) return _clip(line);
  }
  return lines.isEmpty ? '' : _clip(lines.first);
}

String _clip(String s) => s.length > 40 ? s.substring(0, 40) : s;

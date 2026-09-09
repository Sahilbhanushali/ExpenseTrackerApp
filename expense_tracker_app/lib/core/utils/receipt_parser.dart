import 'expense_parser.dart';
import 'money.dart';

/// Port of expense_bot/parser.py's parse_receipt_text() — best-effort parse
/// of OCR'd receipt text into the same shape parseMessage() returns.
/// Prefers a line saying "total" (not "subtotal"); falls back to the
/// largest number on the receipt. Always expense, dated today — OCR text
/// has no notion of income vs. expense or a stated date.
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

final RegExp _totalLineRe = RegExp(r'\btotal\b', caseSensitive: false);
final RegExp _subtotalLineRe = RegExp(
  r'\bsub[\s-]?total\b',
  caseSensitive: false,
);

ParsedReceipt parseReceiptText(
  String text, {
  Map<String, List<String>>? extraCategories,
}) {
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  double? amount;
  for (final line in lines) {
    if (_totalLineRe.hasMatch(line) && !_subtotalLineRe.hasMatch(line)) {
      final found = findAmount(line);
      if (found != null) {
        amount = found.$1;
        break;
      }
    }
  }

  if (amount == null) {
    final candidates = <double>[];
    for (final line in lines) {
      final found = findAmount(line);
      if (found != null) candidates.add(found.$1);
    }
    if (candidates.isNotEmpty) {
      amount = candidates.reduce((a, b) => a > b ? a : b);
    }
  }

  final fullTextLower = lines.join('\n').toLowerCase();
  final category = detectCategory(fullTextLower, extraCategories);
  final note = lines.isNotEmpty
      ? (lines.first.length > 40 ? lines.first.substring(0, 40) : lines.first)
      : '';

  return ParsedReceipt(
    amountPaise: amount == null ? null : rupeesToPaise(amount),
    category: category,
    note: note,
  );
}

import '../constants/categories.dart';
import 'money.dart';

enum ParsedTxnType {
  expense,
  income,
  lent,
  borrowed,
  repayment,
  emiPayment,
  emiCreate,
}

/// Result of parsing one free-text entry — port of expense_bot/parser.py's
/// parse_message() return shape.
class ParsedTransaction {
  /// In paise.
  final int? amountPaise;
  final String category;
  final String note;
  final ParsedTxnType type;
  final String? counterparty;
  final String date; // 'YYYY-MM-DD'
  /// Only set when [type] is emiCreate — total installment count. [amount]
  /// carries the monthly payment for that case, not a one-off total.
  final int? emiMonths;

  /// Only set for lent/borrowed when the message named both how much has
  /// already changed hands and how much is still pending — the amount left
  /// owing, kept alongside the (already-applied) [amount].
  /// In paise.
  final int? pendingAmountPaise;

  const ParsedTransaction({
    required this.amountPaise,
    required this.category,
    required this.note,
    required this.type,
    required this.counterparty,
    required this.date,
    this.emiMonths,
    this.pendingAmountPaise,
  });
}

const Map<String, int> _monthNames = {
  'jan': 1,
  'january': 1,
  'feb': 2,
  'february': 2,
  'mar': 3,
  'march': 3,
  'apr': 4,
  'april': 4,
  'may': 5,
  'jun': 6,
  'june': 6,
  'jul': 7,
  'july': 7,
  'aug': 8,
  'august': 8,
  'sep': 9,
  'sept': 9,
  'september': 9,
  'oct': 10,
  'october': 10,
  'nov': 11,
  'november': 11,
  'dec': 12,
  'december': 12,
};

final RegExp _amountRe = RegExp(
  r'(?:rs\.?|inr|₹)?\s*'
  r'(?<num>\d[\d,]*(?:\.\d+)?)'
  r'\s*'
  r'(?<suffix>lakhs|lakh|lacs|lac|k(?![a-zA-Z])|l(?![a-zA-Z]))?'
  r'\s*'
  r'(?:rs\.?|/-|₹)?',
  caseSensitive: false,
);

const Map<String, double> _suffixMultiplier = {
  'k': 1000,
  'l': 100000,
  'lac': 100000,
  'lacs': 100000,
  'lakh': 100000,
  'lakhs': 100000,
};

final RegExp _relativeDateRe = RegExp(
  r'\b(day before yesterday|yesterday|today)\b',
  caseSensitive: false,
);
final RegExp _daysAgoRe = RegExp(
  r'\b(\d+)\s+days?\s+ago\b',
  caseSensitive: false,
);
final RegExp _monthAlt = RegExp(
  r'\bon\s+(\d{1,2})(?:st|nd|rd|th)?\s+('
  '${_monthNames.keys.toList().join('|')}'
  r')\s*(\d{4})?\b',
  caseSensitive: false,
);

final RegExp _monthsCountRe = RegExp(
  r'(\d+)\s*months?\b',
  caseSensitive: false,
);
final RegExp _monthlyAmountRe = RegExp(
  r'(?:pay|paying|instalment|installment|emi)\s*(?:of\s*)?(?:rs\.?|₹)?\s*(\d[\d,]*(?:\.\d+)?)',
  caseSensitive: false,
);
final RegExp _perMonthAmountRe = RegExp(
  r'(?:rs\.?|₹)?\s*(\d[\d,]*(?:\.\d+)?)\s*(?:per month|/month|every month|each month|a month)',
  caseSensitive: false,
);
final RegExp _anyNumberRe = RegExp(r'\d[\d,]*(?:\.\d+)?');
final RegExp _givenKeywordRe = RegExp(r'\bgiven\b', caseSensitive: false);
final RegExp _pendingKeywordRe = RegExp(r'\bpending\b', caseSensitive: false);

final RegExp _counterpartyRe = RegExp(r'\b(?:to|from)\s+([A-Za-z][A-Za-z]*)');
const Set<String> _counterpartyStopwords = {
  'be',
  'get',
  'pay',
  'give',
  'him',
  'her',
  'them',
  'it',
  'us',
  'the',
  'my',
  'our',
  'your',
  'his',
  'its',
  'do',
  'go',
  'come',
  'take',
  'make',
  'this',
  'that',
  'me',
  'you',
};

(double, (int, int))? findAmount(String message) {
  (double, (int, int), bool)? best;
  for (final m in _amountRe.allMatches(message)) {
    final numStr = m.namedGroup('num');
    if (numStr == null || numStr.isEmpty) continue;
    final value0 = double.tryParse(numStr.replaceAll(',', ''));
    if (value0 == null) continue;

    var value = value0;
    final suffix = (m.namedGroup('suffix') ?? '').toLowerCase();
    if (suffix.isNotEmpty) {
      value *= _suffixMultiplier[suffix] ?? 1;
    }

    final span = (m.start, m.end);
    final matchedText = message.substring(span.$1, span.$2).toLowerCase();
    final hasSignal =
        suffix.isNotEmpty ||
        matchedText.contains('rs') ||
        matchedText.contains('₹') ||
        matchedText.contains('inr') ||
        numStr.replaceAll(',', '').length >= 2;

    if (best == null) {
      best = (value, span, hasSignal);
    } else if (hasSignal && !best.$3) {
      best = (value, span, hasSignal);
    } else if (best.$3) {
      break;
    }
  }
  if (best == null) return null;
  return (best.$1, best.$2);
}

(String, (int, int))? _findDate(String message) {
  final abs = _monthAlt.firstMatch(message);
  if (abs != null) {
    final day = int.parse(abs.group(1)!);
    final month = _monthNames[abs.group(2)!.toLowerCase()]!;
    final year = abs.group(3) != null
        ? int.parse(abs.group(3)!)
        : DateTime.now().year;
    try {
      final d = DateTime(year, month, day);
      if (d.month != month) {
        return null; // invalid day (e.g. Feb 30) rolled over
      }
      return (_isoDate(d), (abs.start, abs.end));
    } catch (_) {
      return null;
    }
  }

  final daysAgo = _daysAgoRe.firstMatch(message);
  if (daysAgo != null) {
    final n = int.parse(daysAgo.group(1)!);
    final d = DateTime.now().subtract(Duration(days: n));
    return (_isoDate(d), (daysAgo.start, daysAgo.end));
  }

  final rel = _relativeDateRe.firstMatch(message);
  if (rel != null) {
    final word = rel.group(1)!.toLowerCase();
    final offset = {
      'today': 0,
      'yesterday': 1,
      'day before yesterday': 2,
    }[word]!;
    final d = DateTime.now().subtract(Duration(days: offset));
    return (_isoDate(d), (rel.start, rel.end));
  }

  return null;
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _removeSpan(String text, (int, int)? span) {
  if (span == null) return text;
  final (start, end) = span;
  return '${text.substring(0, start)} ${text.substring(end)}';
}

bool _keywordIn(String textLower, String keyword) {
  return RegExp(r'\b' + RegExp.escape(keyword.toLowerCase()) + r'\b')
      .hasMatch(textLower);
}

ParsedTxnType _detectType(String messageLower) {
  // Checked first: "paid back 500 to sachin" would otherwise never match —
  // it contains no lend/borrow word, so without this it falls through to a
  // disconnected plain expense instead of reducing the existing loan.
  for (final kw in kRepayKeywords) {
    if (_keywordIn(messageLower, kw)) return ParsedTxnType.repayment;
  }
  for (final kw in kEmiPaymentKeywords) {
    if (_keywordIn(messageLower, kw)) return ParsedTxnType.emiPayment;
  }
  final hasEmiCreateKeyword = kEmiCreateKeywords.any(
    (kw) => _keywordIn(messageLower, kw),
  );
  if (hasEmiCreateKeyword && _monthsCountRe.hasMatch(messageLower)) {
    return ParsedTxnType.emiCreate;
  }
  for (final kw in kLendKeywords) {
    if (_keywordIn(messageLower, kw)) return ParsedTxnType.lent;
  }
  for (final kw in kBorrowKeywords) {
    if (_keywordIn(messageLower, kw)) return ParsedTxnType.borrowed;
  }
  for (final kw in kIncomeKeywords) {
    if (_keywordIn(messageLower, kw)) return ParsedTxnType.income;
  }
  return ParsedTxnType.expense;
}

class EmiCreateDetails {
  final int months;
  final double monthlyAmount;
  const EmiCreateDetails(this.months, this.monthlyAmount);
}

/// "6 months" + a monthly figure (via "pay X", "X per month", or — failing
/// those — the last number in the message that isn't the months count).
/// Returns null when no months count is present at all, since without one
/// there's nothing to distinguish this from a plain expense.
EmiCreateDetails? extractEmiCreateDetails(String text) {
  final monthsMatch = _monthsCountRe.firstMatch(text);
  if (monthsMatch == null) return null;
  final months = int.tryParse(monthsMatch.group(1)!);
  if (months == null || months <= 0) return null;

  double? monthly;
  final perMonth = _perMonthAmountRe.firstMatch(text);
  if (perMonth != null) {
    monthly = double.tryParse(perMonth.group(1)!.replaceAll(',', ''));
  }
  final payMatch = _monthlyAmountRe.firstMatch(text);
  if (monthly == null && payMatch != null) {
    monthly = double.tryParse(payMatch.group(1)!.replaceAll(',', ''));
  }
  if (monthly == null) {
    final candidates = _anyNumberRe
        .allMatches(text)
        .where((m) => m.start != monthsMatch.start)
        .map((m) => double.tryParse(m.group(0)!.replaceAll(',', '')))
        .whereType<double>()
        .toList();
    if (candidates.isNotEmpty) monthly = candidates.last;
  }
  if (monthly == null || monthly <= 0) return null;
  return EmiCreateDetails(months, monthly);
}

/// The number token closest to [keyword] (before or after it) — handles
/// both "5000 given" and "pending 45000" without caring which side the
/// figure landed on.
double? _nearestNumberTo(String text, RegExp keywordRe) {
  final kwMatch = keywordRe.firstMatch(text);
  if (kwMatch == null) return null;
  Match? closest;
  var bestDist = 1 << 30;
  for (final n in _anyNumberRe.allMatches(text)) {
    final dist = n.start >= kwMatch.end
        ? n.start - kwMatch.end
        : kwMatch.start - n.end;
    if (dist >= 0 && dist < bestDist) {
      bestDist = dist;
      closest = n;
    }
  }
  if (closest == null) return null;
  return double.tryParse(closest.group(0)!.replaceAll(',', ''));
}

/// Item description for an EMI create/payment message — strips every
/// number (there are usually several: price, months, monthly amount) and
/// filler words, unlike [_buildNote] which only removes the one amount
/// span it identified as "the" amount.
String _buildEmiNote(String text) {
  final withoutNumbers = text.replaceAll(_anyNumberRe, ' ');
  final tokens = RegExp(r'[A-Za-z]+')
      .allMatches(withoutNumbers)
      .map((m) => m.group(0)!);
  final kept = tokens.where((t) => !kFillerWords.contains(t.toLowerCase()));
  return kept.join(' ');
}

String? _extractCounterparty(String message) {
  final candidates = _counterpartyRe
      .allMatches(message)
      .map((m) => m.group(1)!)
      .where((name) => !_counterpartyStopwords.contains(name.toLowerCase()))
      .toList();
  if (candidates.isEmpty) return null;
  return _titleCase(candidates.last);
}

String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).toLowerCase()}';

String detectCategory(
  String textLower,
  Map<String, List<String>>? extraCategories,
) {
  if (extraCategories != null) {
    for (final entry in extraCategories.entries) {
      for (final kw in entry.value) {
        if (_keywordIn(textLower, kw)) return entry.key;
      }
    }
  }
  for (final entry in kCategoryKeywords.entries) {
    for (final kw in entry.value) {
      if (_keywordIn(textLower, kw)) return entry.key;
    }
  }
  return kDefaultCategory;
}

String _buildNote(String text, (int, int)? amountSpan) {
  final stripped = _removeSpan(text, amountSpan);
  final tokens = RegExp(r'[A-Za-z]+')
      .allMatches(stripped)
      .map((m) => m.group(0)!);
  final kept = tokens
      .where((t) => !kFillerWords.contains(t.toLowerCase()))
      .toList();
  return kept.join(' ');
}

/// Port of expense_bot/parser.py's parse_message().
ParsedTransaction parseMessage(
  String message, {
  Map<String, List<String>>? extraCategories,
}) {
  final trimmed = message.trim();

  final dateResult = _findDate(trimmed);
  final text = _removeSpan(trimmed, dateResult?.$2);
  final textLower = text.toLowerCase();
  final date = dateResult?.$1 ?? _isoDate(DateTime.now());

  final category = detectCategory(textLower, extraCategories);
  final type = _detectType(textLower);

  if (type == ParsedTxnType.emiCreate) {
    final details = extractEmiCreateDetails(
      text,
    )!; // _detectType already checked
    return ParsedTransaction(
      amountPaise: rupeesToPaise(details.monthlyAmount),
      category: category,
      note: _buildEmiNote(text),
      type: type,
      counterparty: null,
      date: date,
      emiMonths: details.months,
    );
  }

  if (type == ParsedTxnType.emiPayment) {
    final amountResult = findAmount(text);
    final amount = amountResult?.$1;
    return ParsedTransaction(
      amountPaise: amount == null ? null : rupeesToPaise(amount),
      category: category,
      note: _buildEmiNote(text),
      type: type,
      counterparty: null,
      date: date,
    );
  }

  final amountResult = findAmount(text);
  final note = _buildNote(text, amountResult?.$2);

  String outCategory;
  String? counterparty;
  double? pendingAmount;
  var amount = amountResult?.$1;
  if (type == ParsedTxnType.lent ||
      type == ParsedTxnType.borrowed ||
      type == ParsedTxnType.repayment) {
    outCategory = 'lending';
    counterparty = _extractCounterparty(text);
    if (type != ParsedTxnType.repayment) {
      // "50000 5000 given pending 45000" — what's actually changed hands
      // so far is the "given" figure; the loan created should reflect
      // that, not the larger up-front total, with the rest noted as
      // still to be paid.
      final given = _nearestNumberTo(text, _givenKeywordRe);
      final pending = _nearestNumberTo(text, _pendingKeywordRe);
      if (given != null && pending != null) {
        amount = given;
        pendingAmount = pending;
      }
    }
  } else {
    outCategory = type == ParsedTxnType.expense ? category : 'income';
    counterparty = null;
  }

  return ParsedTransaction(
    amountPaise: amount == null ? null : rupeesToPaise(amount),
    category: outCategory,
    note: note,
    type: type,
    counterparty: counterparty,
    date: date,
    pendingAmountPaise: pendingAmount == null
        ? null
        : rupeesToPaise(pendingAmount),
  );
}

final RegExp _splitRe = RegExp(r'\s*(?:\band\b|;|\n)\s*', caseSensitive: false);

/// Port of parse_multi() — splits "450 lunch and 200 auto" into two entries;
/// falls back to a single parse if fewer than two pieces have their own amount.
List<ParsedTransaction> parseMulti(
  String message, {
  Map<String, List<String>>? extraCategories,
}) {
  final trimmed = message.trim();
  final parts = trimmed
      .split(_splitRe)
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.length <= 1) {
    return [parseMessage(trimmed, extraCategories: extraCategories)];
  }

  final parsed = parts
      .map((p) => parseMessage(p, extraCategories: extraCategories))
      .toList();
  final valid = parsed.where((p) => p.amountPaise != null).toList();
  if (valid.length < 2) {
    return [parseMessage(trimmed, extraCategories: extraCategories)];
  }
  return valid;
}

import '../constants/categories.dart';

enum ParsedTxnType { expense, income, lent, borrowed }

/// Result of parsing one free-text entry — port of expense_bot/parser.py's
/// parse_message() return shape.
class ParsedTransaction {
  final double? amount;
  final String category;
  final String note;
  final ParsedTxnType type;
  final String? counterparty;
  final String date; // 'YYYY-MM-DD'

  const ParsedTransaction({
    required this.amount,
    required this.category,
    required this.note,
    required this.type,
    required this.counterparty,
    required this.date,
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

  final amountResult = findAmount(text);
  final category = detectCategory(textLower, extraCategories);
  final type = _detectType(textLower);
  final note = _buildNote(text, amountResult?.$2);

  String outCategory;
  String? counterparty;
  if (type == ParsedTxnType.lent || type == ParsedTxnType.borrowed) {
    outCategory = 'lending';
    counterparty = _extractCounterparty(text);
  } else {
    outCategory = type == ParsedTxnType.expense ? category : 'income';
    counterparty = null;
  }

  final amount = amountResult?.$1;
  return ParsedTransaction(
    amount: amount != null ? double.parse(amount.toStringAsFixed(2)) : null,
    category: outCategory,
    note: note,
    type: type,
    counterparty: counterparty,
    date: dateResult?.$1 ?? _isoDate(DateTime.now()),
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
  final valid = parsed.where((p) => p.amount != null).toList();
  if (valid.length < 2) {
    return [parseMessage(trimmed, extraCategories: extraCategories)];
  }
  return valid;
}

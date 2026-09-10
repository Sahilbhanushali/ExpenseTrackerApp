import 'expense_parser.dart' show detectCategory;
import 'money.dart';

/// Which way the money moved, as stated by the bank.
enum SmsDirection { debit, credit }

/// A bank/UPI transaction message resolved into something loggable.
///
/// Deliberately separate from [ParsedTransaction] (which parses free-form
/// user input like "spent 500 on ola"): bank SMS is structured boilerplate,
/// so it gets its own extraction rules and carries provenance fields
/// (sender, reference number) that a typed message never has.
class ParsedSms {
  /// In paise.
  final int amountPaise;
  final SmsDirection direction;

  /// Merchant/payee as printed in the message, when one is named.
  final String? merchant;

  /// Last 3-4 digits of the account or card, e.g. "1234" from "A/c XX1234".
  final String? accountTail;

  /// Bank's own reference (UPI ref / txn id). The strongest dedupe key we
  /// get — the same payment reaching us twice (SMS + app notification)
  /// carries the same ref.
  final String? referenceNo;

  /// Human name of the bank/wallet, resolved from the sender header
  /// ("VM-HDFCBK" -> "HDFC Bank"). Null when the header isn't recognised.
  final String? bank;

  final DateTime occurredAt;
  final String category;

  /// 0..1. Above [kAutoLogThreshold] the transaction is logged without
  /// asking; below it, it waits in the review queue.
  final double confidence;

  const ParsedSms({
    required this.amountPaise,
    required this.direction,
    required this.occurredAt,
    required this.category,
    required this.confidence,
    this.merchant,
    this.accountTail,
    this.referenceNo,
    this.bank,
  });

  /// What the transaction should read as in the ledger: who was paid, which
  /// bank it moved through, and which account. "Auto-detected" told the
  /// user nothing about a row they didn't type themselves.
  ///
  /// e.g. "Swiggy · HDFC Bank ••1234", "HDFC Bank ••1234", "UPI payment".
  String get describe {
    final parts = <String>[];
    if (merchant != null && merchant!.trim().isNotEmpty) parts.add(merchant!);
    final account = [
      ?bank,
      if (accountTail != null) '••$accountTail',
    ].join(' ');
    if (account.isNotEmpty) parts.add(account);
    if (parts.isEmpty) {
      return direction == SmsDirection.credit
          ? 'Money received'
          : 'Card/UPI payment';
    }
    return parts.join(' · ');
  }

  bool get isAutoLoggable => confidence >= kAutoLogThreshold;

  /// Stable identity for a transaction across sources. Prefers the bank's
  /// own reference; falls back to a composite that is still unique enough
  /// to catch the same message being scanned twice.
  String dedupeKey() {
    if (referenceNo != null) return 'ref:${referenceNo!.toLowerCase()}';
    final day = occurredAt.toIso8601String().split('T').first;
    return 'cmp:$day:$amountPaise:${direction.name}:${accountTail ?? ''}';
  }
}

const double kAutoLogThreshold = 0.75;

/// Why a message was not treated as a transaction. Surfaced so the import
/// screen can explain itself instead of silently swallowing messages.
enum SmsRejection {
  empty,
  personalSender,
  otp,
  notCompleted,
  promotional,
  orderStatus,
  balanceOnly,

  /// The user's own money moving between their own accounts/wallets/cards.
  /// Real, but already counted where it left — not new income.
  selfTransfer,
  noAmount,
  noDirection,

  /// The decisive rule: no account, card, or UPI identity anywhere in the
  /// message. Shop and delivery SMS quote amounts constantly; only a bank
  /// or wallet alert says *which account* the money moved through.
  noAccountIdentity,
}

// ---------------------------------------------------------------------------
// Sender
// ---------------------------------------------------------------------------

/// Indian transactional SMS always arrives from a 6-character alphanumeric
/// header ("VM-HDFCBK", "AD-ICICIB"), assigned by the telco and barred from
/// carrying marketing. A plain phone number is a person, and people texting
/// "paid Rs 500, send it back" are not transactions.
bool looksLikeBankSender(String? sender) {
  if (sender == null || sender.isEmpty) return false;
  return !_phoneSenderRe.hasMatch(sender.trim());
}

final RegExp _phoneSenderRe = RegExp(r'^\+?\d[\d\s\-()]{5,}$');

/// Telco headers are "XX-BANKCD" or "XX-BANKCD-S"; the middle token
/// identifies the sender. Only the common Indian ones are listed — an
/// unknown bank simply goes unnamed rather than guessed at.
const Map<String, String> _bankCodes = {
  'HDFCBK': 'HDFC Bank',
  'HDFCBN': 'HDFC Bank',
  'ICICIB': 'ICICI Bank',
  'ICICIT': 'ICICI Bank',
  'SBIINB': 'SBI',
  'SBIUPI': 'SBI',
  'SBICRD': 'SBI Card',
  'ATMSBI': 'SBI',
  'AXISBK': 'Axis Bank',
  'AXISB': 'Axis Bank',
  'KOTAKB': 'Kotak',
  'BOBSMS': 'Bank of Baroda',
  'BOBTXN': 'Bank of Baroda',
  'PNBSMS': 'PNB',
  'CANBNK': 'Canara Bank',
  'UNIONB': 'Union Bank',
  'IDFCFB': 'IDFC FIRST',
  'INDUSB': 'IndusInd',
  'YESBNK': 'YES Bank',
  'RBLBNK': 'RBL Bank',
  'AUBANK': 'AU Bank',
  'FEDBNK': 'Federal Bank',
  'IOBCHN': 'Indian Overseas Bank',
  'CBSSBI': 'SBI',
  'PYTMPB': 'Paytm',
  'PAYTMB': 'Paytm',
  'PHONPE': 'PhonePe',
  'GPAYIN': 'Google Pay',
  'AMZNPA': 'Amazon Pay',
  'SLICEIT': 'slice',
  'CREDCL': 'CRED',
  'JUPITR': 'Jupiter',
  'FIMONEY': 'Fi',
};

/// "VM-HDFCBK-S" -> "HDFC Bank".
///
/// Payment-app notifications pass their app name ("PhonePe") straight
/// through as the sender, so a header that is already a readable name is
/// returned as-is rather than looked up.
String? bankFromSender(String? sender) {
  if (sender == null || sender.trim().isEmpty) return null;
  final trimmed = sender.trim();
  // A person's number is never a bank name.
  if (_phoneSenderRe.hasMatch(trimmed)) return null;
  for (final token in trimmed.toUpperCase().split(RegExp(r'[-_\s]'))) {
    final name = _bankCodes[token];
    if (name != null) return name;
  }
  // A telco header is all-caps with a dash; anything mixed-case is already
  // a name we set ourselves.
  final looksLikeHeader = RegExp(r'^[A-Z0-9]{2}-[A-Z0-9-]+$').hasMatch(trimmed);
  return looksLikeHeader ? null : trimmed;
}

// ---------------------------------------------------------------------------
// Rejection rules
// ---------------------------------------------------------------------------

/// OTP/verification messages very often contain "Rs X" too ("OTP for txn of
/// Rs 500"), so they must be rejected before amount extraction.
final RegExp _otpRe = RegExp(
  r'\b(otp|one[\s-]?time[\s-]?password|verification code|do not share|never share|'
  r'secure code|passcode|login code)\b',
  caseSensitive: false,
);

/// Marketing. "Spend 5000 and get 10% cashback" parses beautifully as a
/// debit if you let it.
final RegExp _promoRe = RegExp(
  r'\b(offer|cashback up to|% off|discount|sale|deal|coupon|voucher|win |'
  r'congratulations|apply now|click|download|limited period|t&c|'
  r'pre[\s-]?approved|eligible for|upgrade your|lowest price|hurry|'
  r'shop more|use code|claim now|scratch card|reward points|refer)\b',
  caseSensitive: false,
);

/// Requests, schedules and failures move no money.
final RegExp _notCompletedRe = RegExp(
  r'\b(failed|declined|unsuccessful|reversed|cancelled|canceled|has requested|'
  r'is requesting|request for|will be debited|will be charged|'
  r'has been requested|expiring|due on|payment due|minimum amount due|'
  r'statement generated|autopay|scheduled|is active till|recharge is|'
  r'plan of|initiated a refund|refund (?:has been )?initiated|'
  r'(?:will|should) (?:reflect|be credited)|business days|'
  r'is being processed|under process|within \d+\s*(?:-\s*\d+\s*)?'
  r'(?:hours|hrs|days))\b',
  caseSensitive: false,
);

/// Shop/courier updates. These quote a price and a verb ("your order of
/// Rs.499 has been sent") and otherwise look exactly like a payment.
final RegExp _orderStatusRe = RegExp(
  r'\b(shipped|dispatched|out for delivery|delivered|arriving|track your|'
  r'track it|your order|order (?:placed|confirmed|id)|you saved|'
  r'worth rs\.?|coins)\b',
  caseSensitive: false,
);

/// Money moving between the user's own instruments — loading a wallet,
/// or the confirmation that a card bill payment landed.
///
/// These read as textbook credits ("Rs.5,000 credited to your CRED
/// wallet"), but the money was already counted when it left the bank
/// account. Logging them as income double-counts it, and a card-repayment
/// confirmation logged as income is simply backwards.
final RegExp _selfTransferRe = RegExp(
  r'\b(?:credited to your\s+\w*\s*(?:wallet|card\s*account)|'
  r'added to your\s+\w*\s*wallet|loaded to|'
  r'repayment .{0,30}received|payment received for your .{0,20}card|'
  r'towards your .{0,20}card (?:bill|dues|outstanding))\b',
  caseSensitive: false,
);

/// Balance notifications state an amount but no movement.
final RegExp _balanceOnlyRe = RegExp(
  r'\b(available balance|avl bal|avbl bal|a/c balance|closing balance|'
  r'passbook balance|balance against|total balance|balance in your)\b',
  caseSensitive: false,
);

// ---------------------------------------------------------------------------
// Extraction
// ---------------------------------------------------------------------------

final RegExp _amountRe = RegExp(
  r'(?:rs\.?|inr|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',
  caseSensitive: false,
);

/// Trailing form: "500.00 INR", "1,250 Rs"
final RegExp _amountTrailingRe = RegExp(
  r'([0-9][0-9,]*(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr|₹)',
  caseSensitive: false,
);

final RegExp _debitRe = RegExp(
  r'\b(debited|debit|spent|paid|withdrawn|withdrawal|purchased?|sent to|'
  r'transferred to|deducted|charged|payment of)\b',
  caseSensitive: false,
);

final RegExp _creditRe = RegExp(
  r'\b(credited|credit|received|deposited|refunded|added to)\b',
  caseSensitive: false,
);

/// "credit card" / "debit card" / "credit limit" name an instrument, not a
/// direction. Left in place, every credit-card *debit* alert reads as both
/// directions at once and used to be thrown away entirely.
final RegExp _instrumentNoiseRe = RegExp(
  r'\b(credit|debit)\s*(card|limit|lmt|line|score)\b',
  caseSensitive: false,
);

final RegExp _accountTailRe = RegExp(
  r'\b(?:a\/c|ac|acct|account|card|ending|wallet)\s*(?:no\.?|number)?\s*'
  r'[xX*\.]*\s*(\d{3,6})\b',
  caseSensitive: false,
);

/// A UPI handle: "swiggy@ybl", "9876543210@paytm". Deliberately rejects
/// anything followed by a dot, so "support@zomato.com" in a marketing
/// footer isn't mistaken for a payee.
final RegExp _vpaRe = RegExp(
  r'\b[a-z0-9][a-z0-9._-]{1,}@[a-z]{2,}\b(?!\.)',
  caseSensitive: false,
);

/// Names a payment rail, which shop SMS never do.
final RegExp _railRe = RegExp(
  r'\b(upi|imps|neft|rtgs|atm|pos|nach|ecs|net\s?banking|mandate|'
  r'auto\s?debit|e-?mandate)\b',
  caseSensitive: false,
);

final RegExp _refRe = RegExp(
  r'\b(?:upi\s*)?(?:ref(?:erence)?|txn|transaction|utr|rrn)\s*'
  r'(?:no\.?|id|number)?\s*[:\-]?\s*([A-Za-z0-9]{6,25})\b',
  caseSensitive: false,
);

/// "to VPA merchant@upi", "at AMAZON", "to JOHN DOE", "trf to SWIGGY".
/// The optional inner "vpa" keeps that word out of the captured name.
final RegExp _merchantRe = RegExp(
  r'\b(?:to|at|towards|favou?ring|trf to|vpa)\s+(?:vpa\s+)?'
  r'([A-Za-z0-9][A-Za-z0-9&@.\-_ ]{2,40}?)'
  r'(?=\s+(?:on|ref|upi|txn|utr|rrn|dated|thru|through|via|using|from|'
  r'a\/c|avl|bal|info|not you|is|has|was|with)\b|[.,;]|$)',
  caseSensitive: false,
);

/// dd-mm-yy / dd/mm/yyyy / dd-Mon-yy
final RegExp _dateRe = RegExp(
  r'\b(\d{1,2})[-/](\d{1,2}|[A-Za-z]{3})[-/](\d{2,4})\b',
);

const _monthAbbr = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// How far a direction verb may sit from the amount and still be describing
/// it. Real alerts put them side by side ("Rs.500 debited"); junk that
/// happens to contain both usually has a sentence in between.
const int _verbProximityChars = 60;

/// Parses one SMS body into a loggable transaction, or null when the
/// message isn't a completed transaction at all.
///
/// The rules are an allowlist, not a blocklist: a message has to look
/// positively like a bank alert to get through. Blocklisting was tried
/// first and let 8 of 10 junk messages past, because every shop, courier
/// and marketing SMS also quotes an amount next to a verb like "paid".
///
/// [receivedAt] is used as the date when the body doesn't state one.
ParsedSms? parseTransactionSms(
  String body, {
  String? sender,
  DateTime? receivedAt,
  Map<String, List<String>>? extraCategories,
  bool requireAccountIdentity = true,
}) => _parse(
  body,
  sender: sender,
  receivedAt: receivedAt,
  extraCategories: extraCategories,
  requireAccountIdentity: requireAccountIdentity,
).$1;

/// Same as [parseTransactionSms], but also reports why a message was
/// rejected — used by the import screen and by tests.
(ParsedSms?, SmsRejection?) parseTransactionSmsVerbose(
  String body, {
  String? sender,
  DateTime? receivedAt,
  Map<String, List<String>>? extraCategories,
  bool requireAccountIdentity = true,
}) => _parse(
  body,
  sender: sender,
  receivedAt: receivedAt,
  extraCategories: extraCategories,
  requireAccountIdentity: requireAccountIdentity,
);

(ParsedSms?, SmsRejection?) _parse(
  String body, {
  String? sender,
  DateTime? receivedAt,
  Map<String, List<String>>? extraCategories,
  bool requireAccountIdentity = true,
}) {
  if (body.trim().isEmpty) return (null, SmsRejection.empty);

  // Gate 1: a person, not a bank. Cheapest and most decisive check there
  // is — no amount of body text makes a friend's text a transaction.
  if (sender != null && !looksLikeBankSender(sender)) {
    return (null, SmsRejection.personalSender);
  }

  final lower = body.toLowerCase();

  // Gate 2: message shapes that are never a completed transaction.
  if (_otpRe.hasMatch(lower)) return (null, SmsRejection.otp);
  if (_notCompletedRe.hasMatch(lower)) {
    return (null, SmsRejection.notCompleted);
  }
  if (_orderStatusRe.hasMatch(lower)) {
    return (null, SmsRejection.orderStatus);
  }
  if (_promoRe.hasMatch(lower)) return (null, SmsRejection.promotional);
  if (_selfTransferRe.hasMatch(lower)) {
    return (null, SmsRejection.selfTransfer);
  }

  // Gate 3: an amount.
  final amountMatch = _amountMatch(body);
  if (amountMatch == null) return (null, SmsRejection.noAmount);
  final amount = _amountOf(amountMatch);
  if (amount == null || amount <= 0) return (null, SmsRejection.noAmount);

  // Gate 4: a direction verb describing *that* amount, chosen by proximity
  // so "Rs.500 debited ... Avl Lmt" resolves to debit rather than being
  // discarded for mentioning both words.
  //
  // Balance wording is judged here rather than earlier: almost every Indian
  // debit alert ends with "Avl Bal: Rs...", so rejecting on that phrase up
  // front threw away genuine spending. A message is balance-only when it
  // quotes a balance and states no movement at all.
  final direction = _directionFor(body, amountMatch);
  if (direction == null) {
    return (
      null,
      _balanceOnlyRe.hasMatch(lower)
          ? SmsRejection.balanceOnly
          : SmsRejection.noDirection,
    );
  }

  // Gate 5: the account identity. A bank names the account the money left;
  // a shop never does. This is what separates "Rs.499 paid" the payment
  // alert from "Rs.499 paid" the order confirmation.
  //
  // Relaxed for text the user hands over deliberately (the share sheet, the
  // quick-add box): the gate exists because inbox scanning is unattended
  // and silent, and neither of those is true when someone has picked this
  // message and is looking at a preview of it.
  final accountTail = _accountTailRe.firstMatch(body)?.group(1);
  final vpa = _vpaRe.firstMatch(body)?.group(0);
  final hasRail = _railRe.hasMatch(lower);
  if (requireAccountIdentity &&
      accountTail == null &&
      vpa == null &&
      !hasRail) {
    return (null, SmsRejection.noAccountIdentity);
  }

  final referenceNo = _refRe.firstMatch(body)?.group(1);
  final merchant = _extractMerchant(body);
  final statedDate = _extractDate(body);
  final occurredAt = statedDate ?? receivedAt ?? DateTime.now();

  final categorySource = [
    merchant ?? '',
    vpa ?? '',
    body,
  ].join(' ').toLowerCase();
  final category = direction == SmsDirection.credit
      ? kSmsIncomeCategory
      : detectCategory(categorySource, extraCategories);

  return (
    ParsedSms(
      amountPaise: amount,
      direction: direction,
      merchant: merchant,
      accountTail: accountTail,
      referenceNo: referenceNo,
      bank: bankFromSender(sender),
      occurredAt: occurredAt,
      category: category,
      confidence: _score(
        sender: sender,
        referenceNo: referenceNo,
        accountTail: accountTail,
        merchant: merchant,
        hasRail: hasRail,
        hasStatedDate: statedDate != null,
      ),
    ),
    null,
  );
}

/// Confidence is about *how sure we are this is a real transaction*, not
/// about how well we categorised it. Everything reaching here already
/// cleared the gates, so the floor is high; the remaining signals decide
/// auto-log versus review.
double _score({
  required String? sender,
  required String? referenceNo,
  required String? accountTail,
  required String? merchant,
  required bool hasRail,
  required bool hasStatedDate,
}) {
  var score = 0.30;
  if (looksLikeBankSender(sender)) score += 0.20;
  if (accountTail != null) score += 0.20;
  if (referenceNo != null) score += 0.15;
  if (hasRail) score += 0.05;
  if (merchant != null) score += 0.05;
  if (hasStatedDate) score += 0.05;
  return score.clamp(0.0, 1.0);
}

RegExpMatch? _amountMatch(String body) =>
    _amountRe.firstMatch(body) ?? _amountTrailingRe.firstMatch(body);

/// Returns paise, so no rupee-as-double ever reaches the ledger.
int? _amountOf(RegExpMatch match) {
  final rupees = double.tryParse(match.group(1)!.replaceAll(',', ''));
  return rupees == null ? null : rupeesToPaise(rupees);
}

/// Picks the direction verb closest to the amount. Instrument names
/// ("credit card") are blanked first, keeping string offsets intact so the
/// distances stay accurate.
SmsDirection? _directionFor(String body, RegExpMatch amountMatch) {
  final masked = body.replaceAllMapped(
    _instrumentNoiseRe,
    (m) => ' ' * m.group(0)!.length,
  );

  int? nearest(RegExp re) {
    int? best;
    for (final m in re.allMatches(masked)) {
      final gap = m.start >= amountMatch.end
          ? m.start - amountMatch.end
          : amountMatch.start - m.end;
      if (gap < 0) return 0;
      if (best == null || gap < best) best = gap;
    }
    return best;
  }

  final debitGap = nearest(_debitRe);
  final creditGap = nearest(_creditRe);

  if (debitGap == null && creditGap == null) return null;
  if (creditGap == null) {
    return debitGap! <= _verbProximityChars ? SmsDirection.debit : null;
  }
  if (debitGap == null) {
    return creditGap <= _verbProximityChars ? SmsDirection.credit : null;
  }
  final winner = debitGap <= creditGap ? debitGap : creditGap;
  if (winner > _verbProximityChars) return null;
  return debitGap <= creditGap ? SmsDirection.debit : SmsDirection.credit;
}

String? _extractMerchant(String body) {
  final raw = _merchantRe.firstMatch(body)?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  // "to VPA 9876543210@ybl" — the handle is more useful than the digits.
  var cleaned = raw.replaceAll(RegExp(r'\s+'), ' ');
  // "credited to your CRED wallet" names the user's own pot, not a payee.
  cleaned = cleaned.replaceFirst(RegExp(r'^your\s+', caseSensitive: false), '');
  if (cleaned.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(cleaned)) return null;
  return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
}

DateTime? _extractDate(String body) {
  final m = _dateRe.firstMatch(body);
  if (m == null) return null;

  final day = int.tryParse(m.group(1)!);
  final monthRaw = m.group(2)!;
  final month = int.tryParse(monthRaw) ?? _monthAbbr[monthRaw.toLowerCase()];
  var year = int.tryParse(m.group(3)!);
  if (day == null || month == null || year == null) return null;
  if (year < 100) year += 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  return DateTime(year, month, day);
}

/// Category used for credits when nothing better is detected — matches the
/// category the rest of the app already uses for income rows.
const String kSmsIncomeCategory = 'income';

/// Exposed so callers can show why something was skipped without
/// re-deriving the rules.
bool isLikelyNonTransactional(String body) {
  final lower = body.toLowerCase();
  return _otpRe.hasMatch(lower) ||
      _notCompletedRe.hasMatch(lower) ||
      _orderStatusRe.hasMatch(lower) ||
      _selfTransferRe.hasMatch(lower) ||
      _promoRe.hasMatch(lower);
}

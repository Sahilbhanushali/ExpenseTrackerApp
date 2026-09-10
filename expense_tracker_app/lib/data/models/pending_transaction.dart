import '../../core/utils/sms_parser.dart';

/// A transaction detected from a bank SMS or payment-app notification that
/// wasn't confident enough to log automatically, waiting for the user to
/// approve or dismiss it.
class PendingTransaction {
  final int? id;

  /// Dedupe key — unique across every source, so the same payment arriving
  /// as both an SMS and a UPI-app notification only ever queues once.
  final String externalRef;

  /// 'sms' or 'notification'.
  final String source;
  final String? sender;
  final String rawBody;

  /// In paise.
  final int amountPaise;
  final SmsDirection direction;
  final String? merchant;
  final String? accountTail;
  final String category;
  final DateTime occurredAt;
  final double confidence;

  /// 'pending' | 'approved' | 'dismissed'. Approved/dismissed rows are kept
  /// so a re-scan of the same inbox doesn't resurrect something the user
  /// already dealt with.
  final String status;
  final String createdAt;

  const PendingTransaction({
    this.id,
    required this.externalRef,
    required this.source,
    required this.rawBody,
    required this.amountPaise,
    required this.direction,
    required this.category,
    required this.occurredAt,
    required this.confidence,
    required this.createdAt,
    this.sender,
    this.merchant,
    this.accountTail,
    this.status = 'pending',
  });

  factory PendingTransaction.fromParsed(
    ParsedSms parsed, {
    required String source,
    required String rawBody,
    String? sender,
  }) => PendingTransaction(
    externalRef: parsed.dedupeKey(),
    source: source,
    sender: sender,
    rawBody: rawBody,
    amountPaise: parsed.amountPaise,
    direction: parsed.direction,
    merchant: parsed.merchant,
    accountTail: parsed.accountTail,
    category: parsed.category,
    occurredAt: parsed.occurredAt,
    confidence: parsed.confidence,
    createdAt: DateTime.now().toIso8601String(),
  );

  /// What to show as the transaction's note once logged.
  String get displayTitle {
    final account = [
      // Derived from the sender header rather than stored — no column, no
      // migration, and it improves retroactively as codes are added.
      ?bankFromSender(sender),
      if (accountTail != null) '••$accountTail',
    ].join(' ');
    final parts = [
      if (merchant != null && merchant!.trim().isNotEmpty) merchant!,
      if (account.isNotEmpty) account,
    ];
    if (parts.isEmpty) return sender ?? 'Bank transaction';
    return parts.join(' · ');
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'external_ref': externalRef,
    'source': source,
    'sender': sender,
    'raw_body': rawBody,
    'amount': amountPaise,
    'direction': direction.name,
    'merchant': merchant,
    'account_tail': accountTail,
    'category': category,
    'occurred_at': occurredAt.toIso8601String(),
    'confidence': confidence,
    'status': status,
    'created_at': createdAt,
  };

  factory PendingTransaction.fromMap(Map<String, Object?> map) =>
      PendingTransaction(
        id: map['id'] as int?,
        externalRef: map['external_ref'] as String,
        source: map['source'] as String,
        sender: map['sender'] as String?,
        rawBody: map['raw_body'] as String,
        amountPaise: (map['amount'] as num).round(),
        direction: map['direction'] == 'credit'
            ? SmsDirection.credit
            : SmsDirection.debit,
        merchant: map['merchant'] as String?,
        accountTail: map['account_tail'] as String?,
        category: map['category'] as String,
        occurredAt: DateTime.parse(map['occurred_at'] as String),
        confidence: (map['confidence'] as num).toDouble(),
        status: map['status'] as String? ?? 'pending',
        createdAt: map['created_at'] as String,
      );
}

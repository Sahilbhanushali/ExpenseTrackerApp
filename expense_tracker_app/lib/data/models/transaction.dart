/// `refund` is money back for an earlier expense: it reduces spending
/// (never counts as income) and links to the expense via [Transaction.refundOf].
enum TxnType { expense, income, lent, borrowed, refund }

/// Where income came from. Only received income is a transaction; expected
/// income lives in `expected_income` and never touches balances.
enum IncomeSource {
  salary,
  freelance,
  side,
  business,
  bonus,
  incentive,
  reimbursement,
  interest,
  other,
}

String incomeSourceLabel(IncomeSource s) => switch (s) {
  IncomeSource.salary => 'Salary',
  IncomeSource.freelance => 'Freelance',
  IncomeSource.side => 'Side income',
  IncomeSource.business => 'Business',
  IncomeSource.bonus => 'Bonus',
  IncomeSource.incentive => 'Incentive',
  IncomeSource.reimbursement => 'Reimbursement',
  IncomeSource.interest => 'Interest',
  IncomeSource.other => 'Other',
};

IncomeSource? incomeSourceFrom(String? v) =>
    IncomeSource.values.where((s) => s.name == v).firstOrNull;

TxnType txnTypeFromString(String value) => TxnType.values.firstWhere(
  (t) => t.name == value,
  orElse: () => TxnType.expense,
);

class Transaction {
  final int? id;
  final String date;
  final String category;

  /// In paise. ₹100.50 is stored as 10050.
  final int amountPaise;
  final String? note;
  final TxnType type;
  final String createdAt;
  final String? counterparty;
  final int? settled;
  final String? account;
  final int? goalId;

  /// Set when this expense is an EMI installment, pointing at `loans.id`.
  /// Without it, deleting the expense would leave the loan's paid count
  /// one ahead of reality.
  final int? loanId;

  /// Where this row came from: 'manual', 'sms', or 'notification'. Lets the
  /// UI mark auto-detected rows and lets an import know what it already
  /// created.
  final String source;

  /// Dedupe key for auto-detected rows (see [ParsedSms.dedupeKey]) — null
  /// for anything typed by hand.
  final String? externalRef;

  const Transaction({
    this.id,
    required this.date,
    required this.category,
    required this.amountPaise,
    this.note,
    required this.type,
    required this.createdAt,
    this.counterparty,
    this.settled,
    this.account,
    this.goalId,
    this.loanId,
    this.source = 'manual',
    this.externalRef,
    this.incomeSource,
    this.recurringIncome = false,
    this.refundOf,
    this.cardId,
  });

  /// Spent (or refunded) on this credit card rather than from an account:
  /// it adds to the card's outstanding, not to any bank balance.
  final int? cardId;

  /// Income only.
  final IncomeSource? incomeSource;

  /// Income only: expected to repeat (salary, retainer) vs one-off.
  final bool recurringIncome;

  /// Refunds only: the expense this money came back for.
  final int? refundOf;

  bool get isAutoDetected => source != 'manual';

  bool get isLoan => type == TxnType.lent || type == TxnType.borrowed;
  bool get isSettled => settled == 1;

  Transaction copyWith({
    int? id,
    String? date,
    String? category,
    int? amountPaise,
    String? note,
    TxnType? type,
    String? createdAt,
    String? counterparty,
    int? settled,
    String? account,
    int? goalId,
    int? loanId,
    String? source,
    String? externalRef,
    IncomeSource? incomeSource,
    bool? recurringIncome,
    int? refundOf,
    int? cardId,
  }) {
    return Transaction(
      id: id ?? this.id,
      date: date ?? this.date,
      category: category ?? this.category,
      amountPaise: amountPaise ?? this.amountPaise,
      note: note ?? this.note,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      counterparty: counterparty ?? this.counterparty,
      settled: settled ?? this.settled,
      account: account ?? this.account,
      // goalId used to be dropped here, silently unlinking a goal
      // contribution from its goal on any copy.
      goalId: goalId ?? this.goalId,
      loanId: loanId ?? this.loanId,
      source: source ?? this.source,
      externalRef: externalRef ?? this.externalRef,
      incomeSource: incomeSource ?? this.incomeSource,
      recurringIncome: recurringIncome ?? this.recurringIncome,
      refundOf: refundOf ?? this.refundOf,
      cardId: cardId ?? this.cardId,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'date': date,
      'category': category,
      'amount': amountPaise,
      'note': note,
      'type': type.name,
      'created_at': createdAt,
      'counterparty': counterparty,
      'settled': settled,
      'account': account,
      'goal_id': goalId,
      'loan_id': loanId,
      'source': source,
      'external_ref': externalRef,
      'income_source': incomeSource?.name,
      'recurring_income': recurringIncome ? 1 : 0,
      'refund_of': refundOf,
      'card_id': cardId,
    };
  }

  factory Transaction.fromMap(Map<String, Object?> map) {
    return Transaction(
      id: map['id'] as int?,
      date: map['date'] as String,
      category: map['category'] as String,
      amountPaise: (map['amount'] as num).round(),
      note: map['note'] as String?,
      type: txnTypeFromString(map['type'] as String),
      createdAt: map['created_at'] as String,
      counterparty: map['counterparty'] as String?,
      settled: map['settled'] as int?,
      account: map['account'] as String?,
      goalId: map['goal_id'] as int?,
      loanId: map['loan_id'] as int?,
      source: map['source'] as String? ?? 'manual',
      externalRef: map['external_ref'] as String?,
      incomeSource: incomeSourceFrom(map['income_source'] as String?),
      recurringIncome: map['recurring_income'] == 1,
      refundOf: map['refund_of'] as int?,
      cardId: map['card_id'] as int?,
    );
  }
}

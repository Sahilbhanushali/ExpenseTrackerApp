enum TxnType { expense, income, lent, borrowed }

TxnType txnTypeFromString(String value) => TxnType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => TxnType.expense,
    );

class Transaction {
  final int? id;
  final String date;
  final String category;
  final double amount;
  final String? note;
  final TxnType type;
  final String createdAt;
  final String? counterparty;
  final int? settled;
  final String? account;
  final int? goalId;

  const Transaction({
    this.id,
    required this.date,
    required this.category,
    required this.amount,
    this.note,
    required this.type,
    required this.createdAt,
    this.counterparty,
    this.settled,
    this.account,
    this.goalId,
  });

  bool get isLoan => type == TxnType.lent || type == TxnType.borrowed;
  bool get isSettled => settled == 1;

  Transaction copyWith({
    int? id,
    String? date,
    String? category,
    double? amount,
    String? note,
    TxnType? type,
    String? createdAt,
    String? counterparty,
    int? settled,
    String? account,
  }) {
    return Transaction(
      id: id ?? this.id,
      date: date ?? this.date,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      counterparty: counterparty ?? this.counterparty,
      settled: settled ?? this.settled,
      account: account ?? this.account,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'date': date,
      'category': category,
      'amount': amount,
      'note': note,
      'type': type.name,
      'created_at': createdAt,
      'counterparty': counterparty,
      'settled': settled,
      'account': account,
      'goal_id': goalId,
    };
  }

  factory Transaction.fromMap(Map<String, Object?> map) {
    return Transaction(
      id: map['id'] as int?,
      date: map['date'] as String,
      category: map['category'] as String,
      amount: (map['amount'] as num).toDouble(),
      note: map['note'] as String?,
      type: txnTypeFromString(map['type'] as String),
      createdAt: map['created_at'] as String,
      counterparty: map['counterparty'] as String?,
      settled: map['settled'] as int?,
      account: map['account'] as String?,
      goalId: map['goal_id'] as int?,
    );
  }
}

class MoneyAccount {
  final int? id;
  final String name;
  final double openingBalance;
  final bool isDefault;
  final String createdAt;

  const MoneyAccount({
    this.id,
    required this.name,
    this.openingBalance = 0,
    this.isDefault = false,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'opening_balance': openingBalance,
      'is_default': isDefault ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory MoneyAccount.fromMap(Map<String, Object?> map) {
    return MoneyAccount(
      id: map['id'] as int?,
      name: map['name'] as String,
      openingBalance: (map['opening_balance'] as num).toDouble(),
      isDefault: (map['is_default'] as int) == 1,
      createdAt: map['created_at'] as String,
    );
  }
}

class Transfer {
  final int? id;
  final String fromAccount;
  final String toAccount;
  final double amount;
  final String? note;
  final String date;
  final String createdAt;

  const Transfer({
    this.id,
    required this.fromAccount,
    required this.toAccount,
    required this.amount,
    this.note,
    required this.date,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'from_account': fromAccount,
      'to_account': toAccount,
      'amount': amount,
      'note': note,
      'date': date,
      'created_at': createdAt,
    };
  }

  factory Transfer.fromMap(Map<String, Object?> map) {
    return Transfer(
      id: map['id'] as int?,
      fromAccount: map['from_account'] as String,
      toAccount: map['to_account'] as String,
      amount: (map['amount'] as num).toDouble(),
      note: map['note'] as String?,
      date: map['date'] as String,
      createdAt: map['created_at'] as String,
    );
  }
}

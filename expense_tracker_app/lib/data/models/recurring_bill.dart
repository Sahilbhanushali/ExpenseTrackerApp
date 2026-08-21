enum RecurringType { expense, income }

RecurringType recurringTypeFromString(String value) =>
    value == 'income' ? RecurringType.income : RecurringType.expense;

class RecurringBill {
  final int? id;
  final double amount;
  final String category;
  final String? note;
  final int dayOfMonth;
  final String? lastRunMonth;
  final bool active;
  final int? installmentsRemaining;
  final int? loanId;
  final RecurringType type;

  const RecurringBill({
    this.id,
    required this.amount,
    required this.category,
    this.note,
    required this.dayOfMonth,
    this.lastRunMonth,
    this.active = true,
    this.installmentsRemaining,
    this.loanId,
    this.type = RecurringType.expense,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'amount': amount,
      'category': category,
      'note': note,
      'day_of_month': dayOfMonth,
      'last_run_month': lastRunMonth,
      'active': active ? 1 : 0,
      'installments_remaining': installmentsRemaining,
      'loan_id': loanId,
      'type': type.name,
    };
  }

  factory RecurringBill.fromMap(Map<String, Object?> map) {
    return RecurringBill(
      id: map['id'] as int?,
      amount: (map['amount'] as num).toDouble(),
      category: map['category'] as String,
      note: map['note'] as String?,
      dayOfMonth: map['day_of_month'] as int,
      lastRunMonth: map['last_run_month'] as String?,
      active: (map['active'] as int) == 1,
      installmentsRemaining: map['installments_remaining'] as int?,
      loanId: map['loan_id'] as int?,
      type: recurringTypeFromString(map['type'] as String? ?? 'expense'),
    );
  }
}

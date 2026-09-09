/// An interest-bearing installment loan (bank loan, card EMI, etc.) — distinct
/// from [RecurringBill]'s flat no-interest installments. Tracks principal,
/// interest, and a fixed monthly EMI so outstanding balance and the next due
/// date/amount can be shown precisely.
class Loan {
  final int? id;
  final String name;

  /// All in paise.
  final int principalPaise;
  final int interestPaise;
  final int emiPaise;
  final int tenureMonths;
  final int installmentsPaid;
  final DateTime startDate;
  final String? note;
  final String? account;
  final bool active;

  const Loan({
    this.id,
    required this.name,
    required this.principalPaise,
    this.interestPaise = 0,
    required this.emiPaise,
    required this.tenureMonths,
    this.installmentsPaid = 0,
    required this.startDate,
    this.note,
    this.account,
    this.active = true,
  });

  int get totalPayablePaise => principalPaise + interestPaise;

  int get outstandingPaise => (totalPayablePaise - emiPaise * installmentsPaid)
      .clamp(0, totalPayablePaise);

  int get installmentsRemaining =>
      (tenureMonths - installmentsPaid).clamp(0, tenureMonths);

  bool get isFullyPaid => installmentsPaid >= tenureMonths;

  /// The start date *is* the first installment's due date — a card EMI is
  /// charged on the day the purchase is converted, not a month later. So
  /// installment N (0-indexed) falls N months after the start, and the last
  /// one at (tenure - 1) months.
  DateTime get endDate => _addMonths(startDate, tenureMonths - 1);

  /// Null once fully paid off.
  DateTime? get nextDueDate =>
      isFullyPaid ? null : _addMonths(startDate, installmentsPaid);

  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month - 1 + months;
    final year = date.year + totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final lastDayOfMonth = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, date.day.clamp(1, lastDayOfMonth));
  }

  Loan copyWith({int? installmentsPaid, bool? active}) => Loan(
    id: id,
    name: name,
    principalPaise: principalPaise,
    interestPaise: interestPaise,
    emiPaise: emiPaise,
    tenureMonths: tenureMonths,
    installmentsPaid: installmentsPaid ?? this.installmentsPaid,
    startDate: startDate,
    note: note,
    account: account,
    active: active ?? this.active,
  );

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'principal': principalPaise,
      'interest_amount': interestPaise,
      'emi_amount': emiPaise,
      'tenure_months': tenureMonths,
      'installments_paid': installmentsPaid,
      'start_date': startDate.toIso8601String(),
      'note': note,
      'account': account,
      'active': active ? 1 : 0,
    };
  }

  factory Loan.fromMap(Map<String, Object?> map) {
    return Loan(
      id: map['id'] as int?,
      name: map['name'] as String,
      principalPaise: (map['principal'] as num).round(),
      interestPaise: (map['interest_amount'] as num?)?.round() ?? 0,
      emiPaise: (map['emi_amount'] as num).round(),
      tenureMonths: map['tenure_months'] as int,
      installmentsPaid: map['installments_paid'] as int? ?? 0,
      startDate: DateTime.parse(map['start_date'] as String),
      note: map['note'] as String?,
      account: map['account'] as String?,
      active: (map['active'] as int) == 1,
    );
  }
}

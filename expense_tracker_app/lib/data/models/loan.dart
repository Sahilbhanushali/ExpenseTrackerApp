/// An interest-bearing installment loan (bank loan, card EMI, etc.) — distinct
/// from [RecurringBill]'s flat no-interest installments. Tracks principal,
/// interest, and a fixed monthly EMI so outstanding balance and the next due
/// date/amount can be shown precisely.
class Loan {
  final int? id;
  final String name;
  final double principal;
  final double interestAmount;
  final double emiAmount;
  final int tenureMonths;
  final int installmentsPaid;
  final DateTime startDate;
  final String? note;
  final String? account;
  final bool active;

  const Loan({
    this.id,
    required this.name,
    required this.principal,
    this.interestAmount = 0,
    required this.emiAmount,
    required this.tenureMonths,
    this.installmentsPaid = 0,
    required this.startDate,
    this.note,
    this.account,
    this.active = true,
  });

  double get totalPayable => principal + interestAmount;

  double get outstanding =>
      (totalPayable - emiAmount * installmentsPaid).clamp(0, totalPayable);

  int get installmentsRemaining =>
      (tenureMonths - installmentsPaid).clamp(0, tenureMonths);

  bool get isFullyPaid => installmentsPaid >= tenureMonths;

  DateTime get endDate => _addMonths(startDate, tenureMonths);

  /// Null once fully paid off.
  DateTime? get nextDueDate =>
      isFullyPaid ? null : _addMonths(startDate, installmentsPaid + 1);

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
    principal: principal,
    interestAmount: interestAmount,
    emiAmount: emiAmount,
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
      'principal': principal,
      'interest_amount': interestAmount,
      'emi_amount': emiAmount,
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
      principal: (map['principal'] as num).toDouble(),
      interestAmount: (map['interest_amount'] as num?)?.toDouble() ?? 0,
      emiAmount: (map['emi_amount'] as num).toDouble(),
      tenureMonths: map['tenure_months'] as int,
      installmentsPaid: map['installments_paid'] as int? ?? 0,
      startDate: DateTime.parse(map['start_date'] as String),
      note: map['note'] as String?,
      account: map['account'] as String?,
      active: (map['active'] as int) == 1,
    );
  }
}

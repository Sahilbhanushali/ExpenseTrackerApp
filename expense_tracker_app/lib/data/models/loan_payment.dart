/// One logged installment against a lending/borrowing record — lets the
/// lending screen show a running history instead of just the current
/// outstanding total, since [TransactionRepository.repay] mutates that
/// total in place.
class LoanPayment {
  final int? id;
  final int loanId;
  final double amount;
  final String date;
  final String? note;
  final String createdAt;

  const LoanPayment({
    this.id,
    required this.loanId,
    required this.amount,
    required this.date,
    this.note,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'loan_id': loanId,
      'amount': amount,
      'date': date,
      'note': note,
      'created_at': createdAt,
    };
  }

  factory LoanPayment.fromMap(Map<String, Object?> map) {
    return LoanPayment(
      id: map['id'] as int?,
      loanId: map['loan_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      note: map['note'] as String?,
      createdAt: map['created_at'] as String,
    );
  }
}

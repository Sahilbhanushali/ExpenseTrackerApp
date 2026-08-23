import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/data/models/loan.dart';

void main() {
  Loan loan({int installmentsPaid = 0}) => Loan(
    name: 'Fridge card EMI',
    principal: 55792,
    interestAmount: 2632,
    emiAmount: 9737.39,
    tenureMonths: 6,
    installmentsPaid: installmentsPaid,
    startDate: DateTime(2026, 4, 17),
  );

  test('totalPayable is principal plus interest', () {
    expect(loan().totalPayable, closeTo(58424, 0.01));
  });

  test('outstanding decreases by one EMI per installment paid', () {
    expect(loan(installmentsPaid: 0).outstanding, closeTo(58424, 0.01));
    expect(loan(installmentsPaid: 1).outstanding, closeTo(48686.61, 0.01));
  });

  test('outstanding never goes negative once overpaid past total', () {
    expect(loan(installmentsPaid: 10).outstanding, 0);
  });

  test('installmentsRemaining and isFullyPaid track tenure', () {
    final l = loan(installmentsPaid: 5);
    expect(l.installmentsRemaining, 1);
    expect(l.isFullyPaid, isFalse);

    final done = loan(installmentsPaid: 6);
    expect(done.installmentsRemaining, 0);
    expect(done.isFullyPaid, isTrue);
    expect(done.nextDueDate, isNull);
  });

  test('nextDueDate steps one month at a time from startDate', () {
    // start 17 Apr 2026: the 5th installment (4 paid) is due 17 Sep, the
    // 6th and final one 17 Oct — same date the loan's endDate lands on.
    final l = loan(installmentsPaid: 4);
    expect(l.nextDueDate, DateTime(2026, 9, 17));
    expect(loan(installmentsPaid: 5).nextDueDate, DateTime(2026, 10, 17));
  });

  test('endDate is startDate plus the full tenure', () {
    expect(loan().endDate, DateTime(2026, 10, 17));
  });

  test('nextDueDate clamps to the last day of a shorter month', () {
    final l = Loan(
      name: 'Short loan',
      principal: 1000,
      emiAmount: 500,
      tenureMonths: 2,
      startDate: DateTime(2026, 1, 31),
      installmentsPaid: 0,
    );
    // Jan 31 + 1 month has no 31st in Feb 2026 (not a leap year).
    expect(l.nextDueDate, DateTime(2026, 2, 28));
  });
}

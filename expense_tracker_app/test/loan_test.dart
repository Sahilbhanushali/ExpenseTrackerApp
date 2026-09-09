import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/data/models/loan.dart';

void main() {
  // Amounts in paise: ₹55,792 principal, ₹2,632 interest, ₹9,737.39 EMI.
  Loan loan({int installmentsPaid = 0}) => Loan(
    name: 'Fridge card EMI',
    principalPaise: 5579200,
    interestPaise: 263200,
    emiPaise: 973739,
    tenureMonths: 6,
    installmentsPaid: installmentsPaid,
    startDate: DateTime(2026, 4, 17),
  );

  test('totalPayablePaise is principal plus interest', () {
    expect(loan().totalPayablePaise, 5842400);
  });

  test('outstanding decreases by one EMI per installment paid', () {
    expect(loan(installmentsPaid: 0).outstandingPaise, 5842400);
    expect(loan(installmentsPaid: 1).outstandingPaise, 4868661);
  });

  test('outstanding never goes negative once overpaid past total', () {
    expect(loan(installmentsPaid: 10).outstandingPaise, 0);
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

  test('the first installment is due on the start date itself', () {
    // A card EMI is charged the day the purchase is converted, not a month
    // later — so with nothing paid yet, the next due date IS the start.
    expect(loan().nextDueDate, DateTime(2026, 4, 17));
  });

  test('nextDueDate steps one month per installment paid', () {
    // start 17 Apr 2026, 1 paid -> the 2nd installment is due 17 May.
    expect(loan(installmentsPaid: 1).nextDueDate, DateTime(2026, 5, 17));
    expect(loan(installmentsPaid: 4).nextDueDate, DateTime(2026, 8, 17));
  });

  test('endDate is the last installment, not a month past it', () {
    // 6 installments starting 17 Apr run Apr..Sep — the last is 17 Sep.
    expect(loan().endDate, DateTime(2026, 9, 17));
    expect(loan(installmentsPaid: 5).nextDueDate, loan().endDate);
  });

  test('nextDueDate clamps to the last day of a shorter month', () {
    final l = Loan(
      name: 'Short loan',
      principalPaise: 100000,
      emiPaise: 50000,
      tenureMonths: 2,
      startDate: DateTime(2026, 1, 31),
      installmentsPaid: 0,
    );
    // Jan 31 + 1 month has no 31st in Feb 2026 (not a leap year).
    expect(l.copyWith(installmentsPaid: 1).nextDueDate, DateTime(2026, 2, 28));
  });
}

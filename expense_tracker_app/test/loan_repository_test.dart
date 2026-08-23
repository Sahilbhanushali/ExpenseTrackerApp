import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

void main() {
  setUpAll(initFfiSqflite);

  late LoanRepository repo;

  setUp(() {
    repo = LoanRepository(AppDatabase.forTesting());
  });

  test(
    'markPaid increments installments and stays active before the last one',
    () async {
      final id = await repo.add(
        Loan(
          name: 'Fridge',
          principal: 1000,
          emiAmount: 500,
          tenureMonths: 2,
          startDate: DateTime(2026, 1, 1),
        ),
      );

      final finished = await repo.markPaid(id);
      expect(finished, isFalse);

      final loans = await repo.list();
      expect(loans.single.installmentsPaid, 1);
    },
  );

  test('markPaid on the final installment deactivates the loan', () async {
    final id = await repo.add(
      Loan(
        name: 'Fridge',
        principal: 1000,
        emiAmount: 500,
        tenureMonths: 2,
        startDate: DateTime(2026, 1, 1),
        installmentsPaid: 1,
      ),
    );

    final finished = await repo.markPaid(id);
    expect(finished, isTrue);

    // Deactivated loans drop out of list(), same as a paid-off loan
    // disappearing from the active view.
    expect(await repo.list(), isEmpty);
  });

  test('remove soft-deletes a loan out of the active list', () async {
    final id = await repo.add(
      Loan(
        name: 'Bike',
        principal: 2000,
        emiAmount: 1000,
        tenureMonths: 2,
        startDate: DateTime(2026, 1, 1),
      ),
    );

    await repo.remove(id);
    expect(await repo.list(), isEmpty);
  });
}

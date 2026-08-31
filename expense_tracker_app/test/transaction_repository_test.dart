import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

void main() {
  setUpAll(initFfiSqflite);

  late TransactionRepository repo;

  setUp(() {
    repo = TransactionRepository(AppDatabase.forTesting());
  });

  Transaction txn({
    required String date,
    required double amount,
    required TxnType type,
    String category = 'misc',
    int? settled,
  }) => Transaction(
    date: date,
    category: category,
    amount: amount,
    type: type,
    createdAt: '${date}T00:00:00.000',
    settled: settled,
  );

  group('monthTotal', () {
    test(
      'sums expense and income within the month, ignores other months',
      () async {
        await repo.add(
          txn(date: '2026-08-05', amount: 100, type: TxnType.expense),
        );
        await repo.add(
          txn(date: '2026-08-20', amount: 50, type: TxnType.expense),
        );
        await repo.add(
          txn(date: '2026-08-10', amount: 400, type: TxnType.income),
        );
        await repo.add(
          txn(date: '2026-07-31', amount: 999, type: TxnType.expense),
        );

        final total = await repo.monthTotal('2026-08');
        expect(total.expense, 150);
        expect(total.income, 400);
      },
    );
  });

  group('categoryTotals', () {
    test('groups expenses by category, excludes income', () async {
      await repo.add(
        txn(
          date: '2026-08-01',
          amount: 100,
          type: TxnType.expense,
          category: 'food',
        ),
      );
      await repo.add(
        txn(
          date: '2026-08-02',
          amount: 30,
          type: TxnType.expense,
          category: 'food',
        ),
      );
      await repo.add(
        txn(
          date: '2026-08-03',
          amount: 60,
          type: TxnType.expense,
          category: 'transport',
        ),
      );
      await repo.add(
        txn(
          date: '2026-08-04',
          amount: 500,
          type: TxnType.income,
          category: 'salary',
        ),
      );

      final totals = await repo.categoryTotals('2026-08');
      expect(totals, {'food': 130, 'transport': 60});
    });
  });

  group('availableSavings', () {
    test('is income minus expense minus outstanding lent money', () async {
      await repo.add(
        txn(date: '2026-08-01', amount: 1000, type: TxnType.income),
      );
      await repo.add(
        txn(date: '2026-08-02', amount: 400, type: TxnType.expense),
      );
      await repo.add(txn(date: '2026-08-03', amount: 100, type: TxnType.lent));
      await repo.add(
        txn(date: '2026-08-04', amount: 50, type: TxnType.borrowed),
      );

      // 1000 - 400 - 100 (borrowed money deliberately excluded)
      expect(await repo.availableSavings(), 500);
    });
  });

  group('repay', () {
    test(
      'a partial repayment reduces outstanding but leaves it unsettled',
      () async {
        final id = await repo.add(
          txn(date: '2026-08-01', amount: 500, type: TxnType.lent, settled: 0),
        );

        final result = await repo.repay(id, 200);

        expect(result, isNotNull);
        expect(result!.applied, 200);
        expect(result.overpaid, 0);
        expect(result.row.amount, 300);
        expect(result.row.isSettled, isFalse);
      },
    );

    test(
      'a repayment that covers the balance settles it and reports overpay',
      () async {
        final id = await repo.add(
          txn(date: '2026-08-01', amount: 500, type: TxnType.lent, settled: 0),
        );

        final result = await repo.repay(id, 700);

        expect(result!.applied, 500);
        expect(result.overpaid, 200);
        expect(result.row.amount, 0);
        expect(result.row.isSettled, isTrue);
      },
    );

    test('repaying an already-settled loan is a no-op', () async {
      final id = await repo.add(
        txn(date: '2026-08-01', amount: 500, type: TxnType.lent, settled: 1),
      );

      expect(await repo.repay(id, 100), isNull);
    });

    test('each repayment is logged to payment history, newest first', () async {
      final id = await repo.add(
        txn(date: '2026-08-01', amount: 500, type: TxnType.borrowed, settled: 0),
      );

      await repo.repay(id, 200);
      await repo.repay(id, 150);

      final payments = await repo.paymentsFor(id);
      expect(payments, hasLength(2));
      expect(payments[0].amount, 150);
      expect(payments[1].amount, 200);
    });
  });
}

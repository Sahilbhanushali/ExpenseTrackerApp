import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/money.dart';
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
    amountPaise: rupeesToPaise(amount),
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
        expect(total.expense, rupeesToPaise(150));
        expect(total.income, rupeesToPaise(400));
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
      expect(totals, {
        'food': rupeesToPaise(130),
        'transport': rupeesToPaise(60),
      });
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
      expect(await repo.availableSavings(), rupeesToPaise(500));
    });
  });

  group('repay', () {
    test(
      'a partial repayment reduces what is owed, not the original entry',
      () async {
        final id = await repo.add(
          txn(date: '2026-08-01', amount: 500, type: TxnType.lent, settled: 0),
        );

        final result = await repo.repay(id, rupeesToPaise(200));

        expect(result, isNotNull);
        expect(result!.applied, rupeesToPaise(200));
        expect(result.overpaid, 0);
        // B6: the lent entry keeps its amount; the repayment is its own
        // dated movement.
        expect(result.row.amountPaise, rupeesToPaise(500));
        expect(result.remaining, rupeesToPaise(300));
        expect(await repo.personLoanRepaid(), {id: rupeesToPaise(200)});
        expect(result.row.isSettled, isFalse);
      },
    );

    test(
      'a repayment that covers the balance settles it and reports overpay',
      () async {
        final id = await repo.add(
          txn(date: '2026-08-01', amount: 500, type: TxnType.lent, settled: 0),
        );

        final result = await repo.repay(id, rupeesToPaise(700));

        expect(result!.applied, rupeesToPaise(500));
        expect(result.overpaid, rupeesToPaise(200));
        expect(result.row.amountPaise, rupeesToPaise(500));
        expect(result.remaining, 0);
        expect(result.row.isSettled, isTrue);
      },
    );

    test('repaying an already-settled loan is a no-op', () async {
      final id = await repo.add(
        txn(date: '2026-08-01', amount: 500, type: TxnType.lent, settled: 1),
      );

      expect(await repo.repay(id, rupeesToPaise(100)), isNull);
    });

    test('each repayment is logged to payment history, newest first', () async {
      final id = await repo.add(
        txn(
          date: '2026-08-01',
          amount: 500,
          type: TxnType.borrowed,
          settled: 0,
        ),
      );

      await repo.repay(id, rupeesToPaise(200));
      await repo.repay(id, rupeesToPaise(150));

      final payments = await repo.paymentsFor(id);
      expect(payments, hasLength(2));
      expect(payments[0].amountPaise, rupeesToPaise(150));
      expect(payments[1].amountPaise, rupeesToPaise(200));
    });
  });

  group('queryPage account filter', () {
    test('returns only rows for that account', () async {
      for (final account in ['HDFC', 'Cash', null]) {
        await repo.add(
          txn(
            date: '2026-08-05',
            amount: 10,
            type: TxnType.expense,
          ).copyWith(account: account),
        );
      }

      final hdfc = await repo.queryPage(account: 'HDFC');
      expect(hdfc.map((t) => t.account), ['HDFC']);
      expect(await repo.queryPage(), hasLength(3));
    });
  });
}

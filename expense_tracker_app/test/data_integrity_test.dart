import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/loan.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/loan_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

void main() {
  setUpAll(initFfiSqflite);

  late AppDatabase db;
  late TransactionRepository txns;
  late AccountRepository accounts;
  late LoanRepository loans;

  setUp(() {
    db = AppDatabase.forTesting();
    txns = TransactionRepository(db);
    accounts = AccountRepository(db);
    loans = LoanRepository(db);
  });

  Loan emiLoan() => Loan(
    name: 'Fridge EMI',
    principalPaise: 5579200,
    interestPaise: 263235,
    emiPaise: 973739,
    tenureMonths: 6,
    startDate: DateTime(2026, 8, 17),
  );

  Transaction emiExpense() => Transaction(
    date: '2026-09-17',
    category: 'EMI',
    amountPaise: 973739,
    type: TxnType.expense,
    createdAt: DateTime(2026, 9, 17).toIso8601String(),
  );

  group('EMI installments are atomic and reversible', () {
    test(
      'paying writes the expense, history and paid count together',
      () async {
        final id = await loans.add(emiLoan());
        final loan = (await loans.list()).single;

        await loans.payInstallment(loan, emiExpense());

        expect((await loans.list()).single.installmentsPaid, 1);
        expect(await txns.allRows(), hasLength(1));
        expect(
          await txns.paymentsFor(id, ownerType: LoanPaymentOwner.emiLoan),
          hasLength(1),
        );
      },
    );

    test('the logged expense is linked back to its loan', () async {
      final id = await loans.add(emiLoan());
      await loans.payInstallment((await loans.list()).single, emiExpense());

      expect((await txns.allRows()).single.loanId, id);
    });

    test('deleting the expense rolls the loan back', () async {
      final id = await loans.add(emiLoan());
      await loans.payInstallment((await loans.list()).single, emiExpense());
      final expense = (await txns.allRows()).single;

      await txns.deleteById(expense.id!);

      // The paid count must not stay ahead of what was actually paid.
      expect((await loans.list()).single.installmentsPaid, 0);
      expect(
        await txns.paymentsFor(id, ownerType: LoanPaymentOwner.emiLoan),
        isEmpty,
      );
    });

    test('undoing the last EMI payment rolls the loan back too', () async {
      await loans.add(emiLoan());
      await loans.payInstallment((await loans.list()).single, emiExpense());

      await txns.undoLast();

      expect((await loans.list()).single.installmentsPaid, 0);
    });

    test('paying the final installment closes the loan', () async {
      final short = Loan(
        name: 'Two-parter',
        principalPaise: 100000,
        emiPaise: 50000,
        tenureMonths: 2,
        startDate: DateTime(2026, 1, 1),
        installmentsPaid: 1,
      );
      await loans.add(short);

      final finished = await loans.payInstallment(
        (await loans.list()).single,
        emiExpense(),
      );

      expect(finished, isTrue);
      // Closed loans drop out of the active list.
      expect(await loans.list(), isEmpty);
    });
  });

  group('loan payment history is scoped by owner', () {
    test('an EMI loan and a person loan sharing an id stay separate', () async {
      // Person loan: id comes from txns. EMI loan: id comes from loans.
      // Both sequences start at 1, so without owner_type these collide.
      final personLoanId = await txns.add(
        Transaction(
          date: '2026-09-01',
          category: 'lending',
          amountPaise: 500000,
          type: TxnType.lent,
          createdAt: DateTime(2026, 9, 1).toIso8601String(),
          counterparty: 'Ravi',
          settled: 0,
        ),
      );
      await txns.repay(personLoanId, 100000);

      final emiId = await loans.add(emiLoan());
      await loans.payInstallment((await loans.list()).single, emiExpense());

      expect(personLoanId, emiId, reason: 'ids must collide for this test');

      final personPayments = await txns.paymentsFor(personLoanId);
      final emiPayments = await txns.paymentsFor(
        emiId,
        ownerType: LoanPaymentOwner.emiLoan,
      );

      expect(personPayments, hasLength(1));
      expect(personPayments.single.amountPaise, 100000);
      expect(emiPayments, hasLength(1));
      expect(emiPayments.single.amountPaise, 973739);
    });
  });

  group('deleting an account never orphans its history', () {
    Future<void> seed() async {
      await accounts.add('Wallet', 100000);
      await accounts.add('Bank', 0);
      await txns.add(
        Transaction(
          date: '2026-09-01',
          category: 'food',
          amountPaise: 20000,
          type: TxnType.expense,
          createdAt: DateTime(2026, 9, 1).toIso8601String(),
          account: 'Wallet',
        ),
      );
    }

    test(
      'refuses to delete while history exists and no destination given',
      () async {
        await seed();
        final wallet = (await accounts.list()).firstWhere(
          (a) => a.name == 'Wallet',
        );

        expect(await accounts.remove(wallet.id!), isFalse);
        expect(await accounts.list(), hasLength(2));
      },
    );

    test(
      'moves history to the chosen account, keeping the money visible',
      () async {
        await seed();
        final wallet = (await accounts.list()).firstWhere(
          (a) => a.name == 'Wallet',
        );

        expect(await accounts.remove(wallet.id!, reassignTo: 'Bank'), isTrue);

        final balances = await accounts.allBalances();
        expect(balances.containsKey('Wallet'), isFalse);
        // The 200 expense followed the history over to Bank.
        expect(balances['Bank'], -20000);
        expect((await txns.allRows()).single.account, 'Bank');
      },
    );

    test('an account with no history deletes cleanly', () async {
      await accounts.add('Spare', 0);
      final spare = (await accounts.list()).firstWhere(
        (a) => a.name == 'Spare',
      );

      expect(await accounts.linkedRecordCount('Spare'), 0);
      expect(await accounts.remove(spare.id!), isTrue);
    });

    test('transfers move across too', () async {
      await seed();
      await accounts.add('Third', 0);
      await accounts.addTransfer(
        Transfer(
          fromAccount: 'Wallet',
          toAccount: 'Third',
          amountPaise: 30000,
          date: '2026-09-02',
          createdAt: DateTime(2026, 9, 2).toIso8601String(),
        ),
      );
      final wallet = (await accounts.list()).firstWhere(
        (a) => a.name == 'Wallet',
      );

      await accounts.remove(wallet.id!, reassignTo: 'Bank');

      final balances = await accounts.allBalances();
      expect(balances['Third'], 30000);
      expect(balances['Bank'], -50000); // -200 expense, -300 transferred out
    });
  });

  group('batched balances match the per-account calculation', () {
    test('opening balance, txns and transfers all fold in', () async {
      await accounts.add('Wallet', 100000);
      await accounts.add('Bank', 50000);
      await txns.add(
        Transaction(
          date: '2026-09-01',
          category: 'food',
          amountPaise: 20000,
          type: TxnType.expense,
          createdAt: '2026-09-01T00:00:00.000',
          account: 'Wallet',
        ),
      );
      await txns.add(
        Transaction(
          date: '2026-09-02',
          category: 'salary',
          amountPaise: 500000,
          type: TxnType.income,
          createdAt: '2026-09-02T00:00:00.000',
          account: 'Bank',
        ),
      );
      await accounts.addTransfer(
        Transfer(
          fromAccount: 'Bank',
          toAccount: 'Wallet',
          amountPaise: 100000,
          date: '2026-09-03',
          createdAt: '2026-09-03T00:00:00.000',
        ),
      );

      final batched = await accounts.allBalances();

      expect(batched['Wallet'], await accounts.balance('Wallet'));
      expect(batched['Bank'], await accounts.balance('Bank'));
      expect(batched['Wallet'], 180000); // 1000 - 200 + 1000
      expect(batched['Bank'], 450000); // 500 + 5000 - 1000
    });
  });

  group('account names are unique', () {
    test('a duplicate name is rejected by the schema', () async {
      await accounts.add('Wallet', 0);
      expect(() => accounts.add('Wallet', 0), throwsA(anything));
    });
  });
}

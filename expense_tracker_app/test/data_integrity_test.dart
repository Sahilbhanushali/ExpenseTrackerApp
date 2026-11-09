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
    emiPaise: 973739,
    tenureMonths: 6,
    startDate: DateTime(2026, 8, 17),
    account: 'Bank',
  );

  Future<LoanStanding> only() async => (await loans.standings()).single;

  group('EMI installments are atomic and reversible', () {
    setUp(() => accounts.add('Bank', 10000000));

    test('paying splits principal (movement) from interest (expense)', () async {
      await loans.add(emiLoan());
      final first = (await only()).next!;
      final r = await loans.payInstallment(
        (await only()).loan.id!,
        date: DateTime(2026, 8, 17),
        account: 'Bank',
      );
      expect(r.interest + r.principal, first.amount);
      // Only interest is spending (rule 4); principal lowers the debt (rule 3).
      expect((await txns.monthTotal('2026-08')).expense, r.interest);
      expect((await only()).outstandingPrincipal, 5579200 - r.principal);
      expect(await accounts.balance('Bank'), 10000000 - first.amount);
    });

    test('deleting the interest entry undoes the whole payment', () async {
      await loans.add(emiLoan());
      final id = (await only()).loan.id!;
      await loans.payInstallment(
        id,
        date: DateTime(2026, 8, 17),
        account: 'Bank',
      );
      final interestTxn = (await txns.queryPage()).single;
      await txns.deleteById(interestTxn.id!);
      final l = await only();
      expect(l.outstandingPrincipal, 5579200);
      expect(l.paidCount, 0);
      expect(await accounts.balance('Bank'), 10000000);
    });

    test('undoing the last payment rolls the loan back too', () async {
      await loans.add(emiLoan());
      final id = (await only()).loan.id!;
      await loans.payInstallment(
        id,
        date: DateTime(2026, 8, 17),
        account: 'Bank',
      );
      expect(await loans.undoLastPayment(id), isTrue);
      expect((await only()).paidCount, 0);
      expect(await loans.undoLastPayment(id), isFalse);
      expect(await accounts.balance('Bank'), 10000000);
    });

    test('paying the final installment closes the loan', () async {
      await loans.add(emiLoan());
      final id = (await only()).loan.id!;
      late LoanPaymentResult r;
      for (var i = 0; i < 6; i++) {
        r = await loans.payInstallment(
          id,
          date: DateTime(2026, 9, 1),
          account: 'Bank',
        );
      }
      expect(r.loanClosed, isTrue);
      final l = await only();
      expect(l.closed, isTrue);
      expect(l.outstandingPrincipal, 0);
      // Total interest equals the user's own EMI × months − principal.
      expect(l.interestPaid, 973739 * 6 - 5579200);
    });
  });

  group('loan payment history is scoped by owner', () {
    test('an EMI loan and a person loan sharing an id stay separate', () async {
      await accounts.add('Bank', 10000000);
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
      await loans.payInstallment(
        emiId,
        date: DateTime(2026, 9, 17),
        account: 'Bank',
      );

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

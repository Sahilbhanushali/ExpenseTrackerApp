import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/money.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

void main() {
  setUpAll(initFfiSqflite);

  late AccountRepository accounts;
  late TransactionRepository txns;

  setUp(() {
    final db = AppDatabase.forTesting();
    accounts = AccountRepository(db);
    txns = TransactionRepository(db);
  });

  Transaction txn({
    required String account,
    required double amount,
    required TxnType type,
  }) => Transaction(
    date: '2026-08-01',
    category: 'misc',
    amountPaise: rupeesToPaise(amount),
    type: type,
    createdAt: '2026-08-01T00:00:00.000',
    account: account,
  );

  test('balance is opening balance when there are no transactions', () async {
    await accounts.add('Wallet', rupeesToPaise(500));
    expect(await accounts.balance('Wallet'), rupeesToPaise(500));
  });

  test(
    'expense and lent reduce balance; income and borrowed add to it',
    () async {
      await accounts.add('Wallet', rupeesToPaise(1000));
      await txns.add(
        txn(account: 'Wallet', amount: 200, type: TxnType.expense),
      );
      await txns.add(txn(account: 'Wallet', amount: 300, type: TxnType.income));
      await txns.add(txn(account: 'Wallet', amount: 100, type: TxnType.lent));
      await txns.add(
        txn(account: 'Wallet', amount: 50, type: TxnType.borrowed),
      );

      // 1000 - 200 + 300 - 100 + 50
      expect(await accounts.balance('Wallet'), rupeesToPaise(1050));
    },
  );

  test('transfers move balance between accounts', () async {
    await accounts.add('Wallet', rupeesToPaise(1000));
    await accounts.add('Bank', rupeesToPaise(0));
    await accounts.addTransfer(
      Transfer(
        fromAccount: 'Wallet',
        toAccount: 'Bank',
        amountPaise: rupeesToPaise(400),
        date: '2026-08-01',
        createdAt: '2026-08-01T00:00:00.000',
      ),
    );

    expect(await accounts.balance('Wallet'), rupeesToPaise(600));
    expect(await accounts.balance('Bank'), rupeesToPaise(400));
  });

  test('balance is null for an account that does not exist', () async {
    expect(await accounts.balance('Ghost'), isNull);
  });

  test('renaming an account carries its transaction history forward', () async {
    final id = await accounts.add('Old', rupeesToPaise(100));
    await txns.add(txn(account: 'Old', amount: 50, type: TxnType.expense));

    await accounts.update(id, name: 'New');

    expect(await accounts.balance('New'), rupeesToPaise(50));
    expect(await accounts.balance('Old'), isNull);
  });

  group('per-account history', () {
    Transfer transfer(String from, String to, String date) => Transfer(
      fromAccount: from,
      toAccount: to,
      amountPaise: 5000,
      date: date,
      createdAt: '${date}T00:00:00.000',
    );

    test('transfersFor returns both directions, newest first', () async {
      await accounts.addTransfer(transfer('Cash', 'HDFC', '2026-08-01'));
      await accounts.addTransfer(transfer('HDFC', 'Wallet', '2026-08-03'));
      await accounts.addTransfer(transfer('Cash', 'Wallet', '2026-08-02'));

      final hdfc = await accounts.transfersFor('HDFC');
      expect(hdfc.map((t) => t.date), ['2026-08-03', '2026-08-01']);

      final ranged = await accounts.transfersFor(
        'HDFC',
        from: DateTime(2026, 8, 2),
        to: DateTime(2026, 8, 31),
      );
      expect(ranged, hasLength(1));
    });

    test('unassigned rows are counted and can be assigned', () async {
      final id = await txns.add(
        const Transaction(
          date: '2026-08-01',
          category: 'misc',
          amountPaise: 1000,
          type: TxnType.expense,
          createdAt: '2026-08-01T00:00:00.000',
        ),
      );
      expect(await accounts.unassignedTxnCount(), 1);
      expect(await txns.queryPage(unassignedOnly: true), hasLength(1));

      await txns.update(id, account: 'HDFC');
      expect(await accounts.unassignedTxnCount(), 0);
      expect(await txns.queryPage(account: 'HDFC'), hasLength(1));
    });
  });
}

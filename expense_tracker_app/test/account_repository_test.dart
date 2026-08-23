import 'package:flutter_test/flutter_test.dart';

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
    amount: amount,
    type: type,
    createdAt: '2026-08-01T00:00:00.000',
    account: account,
  );

  test('balance is opening balance when there are no transactions', () async {
    await accounts.add('Wallet', 500);
    expect(await accounts.balance('Wallet'), 500);
  });

  test(
    'expense and lent reduce balance; income and borrowed add to it',
    () async {
      await accounts.add('Wallet', 1000);
      await txns.add(
        txn(account: 'Wallet', amount: 200, type: TxnType.expense),
      );
      await txns.add(txn(account: 'Wallet', amount: 300, type: TxnType.income));
      await txns.add(txn(account: 'Wallet', amount: 100, type: TxnType.lent));
      await txns.add(
        txn(account: 'Wallet', amount: 50, type: TxnType.borrowed),
      );

      // 1000 - 200 + 300 - 100 + 50
      expect(await accounts.balance('Wallet'), 1050);
    },
  );

  test('transfers move balance between accounts', () async {
    await accounts.add('Wallet', 1000);
    await accounts.add('Bank', 0);
    await accounts.addTransfer(
      Transfer(
        fromAccount: 'Wallet',
        toAccount: 'Bank',
        amount: 400,
        date: '2026-08-01',
        createdAt: '2026-08-01T00:00:00.000',
      ),
    );

    expect(await accounts.balance('Wallet'), 600);
    expect(await accounts.balance('Bank'), 400);
  });

  test('balance is null for an account that does not exist', () async {
    expect(await accounts.balance('Ghost'), isNull);
  });

  test('renaming an account carries its transaction history forward', () async {
    final id = await accounts.add('Old', 100);
    await txns.add(txn(account: 'Old', amount: 50, type: TxnType.expense));

    await accounts.update(id, name: 'New');

    expect(await accounts.balance('New'), 50);
    expect(await accounts.balance('Old'), isNull);
  });
}

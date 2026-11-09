import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/finance/accounting.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/account.dart';
import 'package:expense_tracker_app/data/models/movement.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/account_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

Transfer _transfer(
  String from,
  String to,
  int paise, {
  MovementStatus status = MovementStatus.completed,
}) => Transfer(
  fromAccount: from,
  toAccount: to,
  amountPaise: paise,
  date: '2026-11-12',
  createdAt: '2026-11-12T10:00:00.000',
  status: status,
);

void main() {
  setUpAll(initFfiSqflite);

  group('v12 -> v13 upgrade', () {
    late Directory tmp;
    late String path;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('spendo_v13');
      path = '${tmp.path}/spendo.db';
    });
    tearDown(() => tmp.delete(recursive: true));

    /// A genuine v12 file: current schema with the v13 additions removed,
    /// then user_version wound back.
    Future<void> seedV12() async {
      final app = AppDatabase.forTesting(path);
      final db = await app.database;
      for (final t in ['postings', 'movements', 'audit_log']) {
        await db.execute('DROP TABLE $t');
      }
      for (final c in ['bank_name', 'last4', 'roles', 'status']) {
        await db.execute('ALTER TABLE accounts DROP COLUMN $c');
      }
      Future<void> account(String name, int opening, String type) =>
          db.insert('accounts', {
            'name': name,
            'opening_balance': opening,
            'is_default': 0,
            'created_at': '2026-01-01T00:00:00.000',
            'type': type,
          });
      await account('Salary', 1000000, 'cash');
      await account('Savings', 500000, 'cash');
      await account('Rainy day', 200000, 'emergency_fund');
      await db.insert('txns', {
        'date': '2026-11-10',
        'category': 'salary',
        'amount': 1900000,
        'type': 'income',
        'created_at': '2026-11-10T00:00:00.000',
        'account': 'Salary',
      });
      await db.insert('transfers', {
        'from_account': 'Salary',
        'to_account': 'Savings',
        'amount': 300000,
        'date': '2026-11-11',
        'created_at': '2026-11-11T00:00:00.000',
      });
      await db.execute('PRAGMA user_version = 12');
      await app.close();
    }

    test('keeps every balance and copies transfers into the ledger', () async {
      await seedV12();
      final app = AppDatabase.forTesting(path);
      final repo = AccountRepository(app);

      expect(await repo.allBalances(), {
        'Salary': 1000000 + 1900000 - 300000,
        'Savings': 500000 + 300000,
        'Rainy day': 200000,
      });
      final db = await app.database;
      final movement = (await db.query('movements')).single;
      expect(movement['ref'], 'legacy-transfer-1');
      final postings = await db.query('postings');
      expect(postings.map((p) => p['amount']), [-300000, 300000]);
      // The old row is left exactly as it was.
      expect((await db.query('transfers')).single['amount'], 300000);

      final roles = {for (final a in await repo.list()) a.name: a.roles};
      expect(roles['Salary'], {AccountRole.daily});
      expect(roles['Rainy day'], {AccountRole.emergency});
      await app.close();
    });

    test('running the step again changes nothing', () async {
      await seedV12();
      var app = AppDatabase.forTesting(path);
      await app.database;
      await app.close();
      final raw = AppDatabase.forTesting(path);
      await (await raw.database).execute('PRAGMA user_version = 12');
      await raw.close();

      app = AppDatabase.forTesting(path);
      final db = await app.database;
      expect(await db.query('movements'), hasLength(1));
      expect(await db.query('postings'), hasLength(2));
      await app.close();
    });
  });

  group('transfers (rule 1)', () {
    late AppDatabase app;
    late AccountRepository accounts;
    late TransactionRepository txns;

    setUp(() async {
      app = AppDatabase.forTesting();
      accounts = AccountRepository(app);
      txns = TransactionRepository(app);
      await accounts.add('Salary', 0);
      await accounts.add('Savings', 0, roles: {AccountRole.savings});
    });

    test('scenario 7: ₹3,000 salary → savings is neither income nor '
        'expense', () async {
      await txns.add(
        const Transaction(
          date: '2026-11-10',
          category: 'salary',
          amountPaise: 1900000,
          type: TxnType.income,
          createdAt: '2026-11-10T00:00:00.000',
          account: 'Salary',
        ),
      );
      await accounts.addTransfer(_transfer('Salary', 'Savings', 300000));

      expect(await accounts.allBalances(), {
        'Salary': 1600000,
        'Savings': 300000,
      });
      final month = await txns.monthTotal('2026-11');
      expect(month.income, 1900000);
      expect(month.expense, 0);

      final db = await app.database;
      final postings = await db.query('postings');
      expect(postings.fold<int>(0, (s, p) => s + (p['amount'] as int)), 0);
      final movementId = postings.first['movement_id'];
      expect(postings.every((p) => p['movement_id'] == movementId), isTrue);
      expect(
        await db.query('audit_log', where: "entity = 'movement'"),
        hasLength(1),
      );
    });

    test(
      'planned transfers change nothing until completed (rule 14)',
      () async {
        final id = await accounts.addTransfer(
          _transfer('Salary', 'Savings', 50000, status: MovementStatus.planned),
        );
        expect((await accounts.allBalances())['Savings'], 0);

        await accounts.setTransferStatus(id, MovementStatus.completed);
        expect((await accounts.allBalances())['Savings'], 50000);

        await accounts.setTransferStatus(id, MovementStatus.cancelled);
        expect((await accounts.allBalances())['Savings'], 0);
        expect(await accounts.transfersFor('Savings'), isEmpty);
      },
    );

    test('a batch is all or nothing', () async {
      await expectLater(
        accounts.addTransfers([
          _transfer('Salary', 'Savings', 1000),
          _transfer('Salary', 'Nowhere', 1000),
        ]),
        throwsStateError,
      );
      final db = await app.database;
      expect(await db.query('movements'), isEmpty);
      expect(await db.query('postings'), isEmpty);
    });

    test('rejects zero amounts and same-account transfers', () {
      expect(
        () => accounts.addTransfer(_transfer('Salary', 'Savings', 0)),
        throwsArgumentError,
      );
      expect(
        () => accounts.addTransfer(_transfer('Salary', 'Salary', 100)),
        throwsArgumentError,
      );
    });

    test('deleting an account moves its transfer history', () async {
      await accounts.add('Wallet', 0);
      await accounts.addTransfer(_transfer('Salary', 'Wallet', 20000));
      final wallet = (await accounts.list()).firstWhere(
        (a) => a.name == 'Wallet',
      );
      expect(await accounts.remove(wallet.id!), isFalse);
      expect(await accounts.remove(wallet.id!, reassignTo: 'Savings'), isTrue);
      expect((await accounts.allBalances())['Savings'], 20000);
    });

    test('opening balance edits are audited, not income (rule 8)', () async {
      final salary = (await accounts.list()).first;
      await accounts.update(salary.id!, openingBalancePaise: 750000);
      expect((await txns.monthTotal('2026-11')).income, 0);
      final db = await app.database;
      final entry = (await db.query(
        'audit_log',
        where: "entity = 'account' AND action = 'update'",
      )).single;
      expect(entry['before_json'], '{"opening_balance":0}');
      expect(entry['after_json'], '{"opening_balance":750000}');
    });

    test('transaction edits and deletes are audited', () async {
      final id = await txns.add(
        const Transaction(
          date: '2026-11-12',
          category: 'food',
          amountPaise: 25000,
          type: TxnType.expense,
          createdAt: '2026-11-12T00:00:00.000',
        ),
      );
      await txns.update(id, amountPaise: 30000);
      await txns.deleteById(id);
      final db = await app.database;
      final actions = (await db.query(
        'audit_log',
        where: "entity = 'txn'",
        orderBy: 'id',
      )).map((r) => r['action']);
      expect(actions, ['update', 'delete']);
    });
  });

  group('accounting rules', () {
    test('only income and expense reach period totals', () {
      expect(countsAsIncome(TxnType.income), isTrue);
      expect(countsAsIncome(TxnType.borrowed), isFalse);
      expect(countsAsExpense(TxnType.expense), isTrue);
      expect(countsAsExpense(TxnType.lent), isFalse);
      expect(txnBalanceEffect(TxnType.lent, 100), -100);
      expect(txnBalanceEffect(TxnType.borrowed, 100), 100);
    });

    test('net worth subtracts EMI loans as well as borrowed money', () {
      const nw = NetWorth(
        accounts: 5000000,
        receivables: 200000,
        borrowed: 100000,
        loans: 1200000,
      );
      expect(nw.assets, 5200000);
      expect(nw.liabilities, 1300000);
      expect(nw.total, 3900000);
    });

    test('savings, emergency and investing accounts are not spendable', () {
      MoneyAccount account(Set<AccountRole> roles, {AccountType? type}) =>
          MoneyAccount(
            name: 'a',
            createdAt: '',
            roles: roles,
            type: type ?? AccountType.cash,
          );
      expect(
        account({AccountRole.salary, AccountRole.daily}).isSpendable,
        isTrue,
      );
      expect(account({AccountRole.savings}).isSpendable, isFalse);
      expect(
        account({AccountRole.salary, AccountRole.emergency}).isSpendable,
        isFalse,
      );
      expect(account({}, type: AccountType.investment).isSpendable, isFalse);
    });
  });
}

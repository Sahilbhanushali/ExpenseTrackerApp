import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/app_config.dart';

import 'helpers/sqflite_ffi_setup.dart';

/// v11 rewrites every money column from rupees to paise, in place, on real
/// user databases. Getting it wrong silently multiplies or divides someone's
/// net worth by 100, so it gets its own test against a genuine v10 file.
void main() {
  setUpAll(initFfiSqflite);

  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('spendo_migration');
    dbPath = '${tmp.path}/spendo.db';
  });

  tearDown(() => tmp.delete(recursive: true));

  /// Builds the current schema, then winds the file back to v10: money
  /// columns back in rupees, user_version back to 10. Reopening it runs the
  /// real v10 -> v11 upgrade path.
  Future<void> seedV10() async {
    final app = AppDatabase.forTesting(dbPath);
    final db = await app.database;

    await db.insert('accounts', {
      'name': 'Wallet',
      'opening_balance': 1000.50,
      'type': 'cash',
      'is_default': 1,
      'current_value': null,
      'created_at': '2026-01-01T00:00:00.000',
    });
    await db.insert('accounts', {
      'name': 'Fund',
      'opening_balance': 5000.0,
      'type': 'investment',
      'is_default': 0,
      'current_value': 5250.75,
      'created_at': '2026-01-01T00:00:00.000',
    });
    await db.insert('txns', {
      'date': '2026-09-01',
      'category': 'food',
      'amount': 9737.39,
      'type': 'expense',
      'created_at': '2026-09-01T00:00:00.000',
      'account': 'Wallet',
    });
    await db.insert('loans', {
      'name': 'Fridge',
      'principal': 55792.0,
      'interest_amount': 2632.35,
      'emi_amount': 9737.39,
      'tenure_months': 6,
      'installments_paid': 0,
      'start_date': '2026-04-17T00:00:00.000',
      'active': 1,
    });

    await db.execute('PRAGMA user_version = 10');
    await app.close();
  }

  test('v10 -> v11 converts every money column to integer paise', () async {
    await seedV10();

    final app = AppDatabase.forTesting(dbPath);
    final db = await app.database;

    final accounts = await db.query('accounts', orderBy: 'name');
    expect(accounts[0]['name'], 'Fund');
    expect(accounts[0]['opening_balance'], 500000);
    expect(accounts[0]['current_value'], 525075);
    expect(accounts[1]['name'], 'Wallet');
    expect(accounts[1]['opening_balance'], 100050);
    // Optional columns must stay NULL, not become 0.
    expect(accounts[1]['current_value'], isNull);

    final txn = (await db.query('txns')).single;
    expect(txn['amount'], 973739);

    final loan = (await db.query('loans')).single;
    expect(loan['principal'], 5579200);
    expect(loan['interest_amount'], 263235);
    expect(loan['emi_amount'], 973739);

    await app.close();
  });

  test('the conversion runs exactly once, not on every open', () async {
    await seedV10();

    for (var i = 0; i < 3; i++) {
      final app = AppDatabase.forTesting(dbPath);
      final db = await app.database;
      expect((await db.query('txns')).single['amount'], 973739);
      await app.close();
    }
  });

  group('config.json', () {
    test('a config without a schema stamp is read as rupees', () {
      final config = AppConfig.fromJson({
        'currency': '₹',
        'monthlyBudget': 25000,
        'savingsGoal': {'amount': 5000.5, 'label': 'Trip'},
        'budgets': {'food': 8000},
      });

      expect(config.monthlyBudgetPaise, 2500000);
      expect(config.savingsGoal.amountPaise, 500050);
      expect(config.budgets['food'], 800000);
    });

    test('a schema-2 config is read as paise, unscaled', () {
      final config = AppConfig.fromJson({
        'schema': 2,
        'monthlyBudget': 2500000,
        'savingsGoal': {'amount': 500050, 'label': 'Trip'},
        'budgets': {'food': 800000},
      });

      expect(config.monthlyBudgetPaise, 2500000);
      expect(config.savingsGoal.amountPaise, 500050);
      expect(config.budgets['food'], 800000);
    });

    test('a round-trip through toJson is stable', () {
      const original = AppConfig(
        monthlyBudgetPaise: 2500000,
        savingsGoal: SavingsGoal(amountPaise: 500050, label: 'Trip'),
        budgets: {'food': 800000},
      );

      final restored = AppConfig.fromJson(
        Map<String, dynamic>.from(original.toJson()),
      );

      expect(restored.monthlyBudgetPaise, original.monthlyBudgetPaise);
      expect(restored.savingsGoal.amountPaise, 500050);
      expect(restored.budgets['food'], 800000);
    });
  });
}

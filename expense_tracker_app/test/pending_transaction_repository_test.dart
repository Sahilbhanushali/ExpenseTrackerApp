import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/sms_parser.dart';
import 'package:expense_tracker_app/data/datasources/app_database.dart';
import 'package:expense_tracker_app/data/models/pending_transaction.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/data/repositories/pending_transaction_repository.dart';
import 'package:expense_tracker_app/data/repositories/transaction_repository.dart';

import 'helpers/sqflite_ffi_setup.dart';

void main() {
  setUpAll(initFfiSqflite);

  late PendingTransactionRepository pending;
  late TransactionRepository txns;

  setUp(() {
    final db = AppDatabase.forTesting();
    pending = PendingTransactionRepository(db);
    txns = TransactionRepository(db);
  });

  PendingTransaction sample({String ref = 'ref:abc123'}) => PendingTransaction(
    externalRef: ref,
    source: 'sms',
    rawBody: 'Rs.500.00 debited from A/c XX1234',
    amountPaise: 50000,
    direction: SmsDirection.debit,
    category: 'food',
    occurredAt: DateTime(2026, 9, 9),
    confidence: 0.5,
    createdAt: DateTime(2026, 9, 9).toIso8601String(),
  );

  test('queues a new detection', () async {
    expect(await pending.add(sample()), isNotNull);
    expect(await pending.pendingCount(), 1);
  });

  test('the same message queued twice only lands once', () async {
    await pending.add(sample());
    final second = await pending.add(sample());

    expect(second, isNull);
    expect(await pending.pendingCount(), 1);
  });

  test('a detection already logged to the ledger is not re-queued', () async {
    await txns.add(
      Transaction(
        date: '2026-09-09',
        category: 'food',
        amountPaise: 50000,
        type: TxnType.expense,
        createdAt: DateTime(2026, 9, 9).toIso8601String(),
        source: 'sms',
        externalRef: 'ref:abc123',
      ),
    );

    expect(await pending.add(sample()), isNull);
    expect(await pending.pendingCount(), 0);
  });

  test(
    'approving removes it from the queue but keeps it as dedupe memory',
    () async {
      final id = await pending.add(sample());
      await pending.setStatus(id!, 'approved');

      expect(await pending.pendingCount(), 0);
      // A re-scan of the same inbox must not resurrect it.
      expect(await pending.add(sample()), isNull);
    },
  );

  test('dismissing keeps it from coming back on the next scan', () async {
    final id = await pending.add(sample());
    await pending.setStatus(id!, 'dismissed');

    expect(await pending.add(sample()), isNull);
    expect(await pending.pendingCount(), 0);
  });

  test('different transactions both queue', () async {
    await pending.add(sample(ref: 'ref:aaa111'));
    await pending.add(sample(ref: 'ref:bbb222'));

    expect(await pending.pendingCount(), 2);
  });

  test('source and external ref round-trip through the ledger', () async {
    await txns.add(
      Transaction(
        date: '2026-09-09',
        category: 'food',
        amountPaise: 50000,
        type: TxnType.expense,
        createdAt: DateTime(2026, 9, 9).toIso8601String(),
        source: 'sms',
        externalRef: 'ref:xyz789',
      ),
    );

    final rows = await txns.allRows();
    expect(rows.single.source, 'sms');
    expect(rows.single.externalRef, 'ref:xyz789');
    expect(rows.single.isAutoDetected, isTrue);
  });

  test('manual transactions default to the manual source', () async {
    await txns.add(
      Transaction(
        date: '2026-09-09',
        category: 'food',
        amountPaise: 10000,
        type: TxnType.expense,
        createdAt: DateTime(2026, 9, 9).toIso8601String(),
      ),
    );

    final rows = await txns.allRows();
    expect(rows.single.source, 'manual');
    expect(rows.single.isAutoDetected, isFalse);
  });
}

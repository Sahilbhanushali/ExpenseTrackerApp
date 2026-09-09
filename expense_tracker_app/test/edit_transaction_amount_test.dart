import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/core/utils/money.dart';
import 'package:expense_tracker_app/data/models/transaction.dart';
import 'package:expense_tracker_app/features/expenses/transactions_screen.dart';

/// Money is stored in paise but typed in rupees, so the edit sheet crosses
/// that boundary twice: once filling the field, once parsing it back. Get
/// either side wrong and every edit silently multiplies the amount by 100 —
/// which is exactly what happened when the field was prefilled with raw
/// paise.
void main() {
  Transaction txn(int amountPaise) => Transaction(
    id: 1,
    date: '2026-09-09',
    category: 'food',
    amountPaise: amountPaise,
    type: TxnType.expense,
    createdAt: '2026-09-09T00:00:00.000',
  );

  Future<String> amountFieldText(WidgetTester tester, int amountPaise) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionDetailSheet(
            // A distinct key per amount, so each pump builds a fresh State
            // instead of reusing the previous one's controller.
            key: ValueKey(amountPaise),
            txn: txn(amountPaise),
            currency: '₹',
            categories: const ['food', 'travel'],
            onDelete: () {},
          ),
        ),
      ),
    );
    final field = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Amount',
      ),
    );
    return field.controller!.text;
  }

  testWidgets('the amount field shows rupees, not paise', (tester) async {
    expect(await amountFieldText(tester, 56000), '560');
  });

  testWidgets('paise are shown when they are non-zero', (tester) async {
    expect(await amountFieldText(tester, 973739), '9737.39');
  });

  testWidgets('opening and saving without editing keeps the amount', (
    tester,
  ) async {
    // The round trip that was broken: 56000p -> "56000.00" -> 5600000p.
    for (final paise in [56000, 973739, 5, 100, 5579200]) {
      final shown = await amountFieldText(tester, paise);
      expect(
        parseRupeesToPaise(shown),
        paise,
        reason: '$paise paise displayed as "$shown"',
      );
    }
  });
}

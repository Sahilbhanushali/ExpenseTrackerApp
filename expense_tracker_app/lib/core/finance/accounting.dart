import '../../data/models/transaction.dart';

/// The app's accounting rules in one place. Pure functions, no I/O, so
/// every screen, report and alert agrees and each rule is unit-tested.
///
/// Rules this file enforces (numbering from docs/finance-upgrade-plan.md):
///  1. Transfers between your accounts are neither income nor expense —
///     they live in `movements`, never in `txns`, so they can't reach the
///     income/expense functions below at all.
///  8. Opening balances are a baseline, not income.
/// 12–14. Planned (approved, not yet done) movements don't change balances;
///     only completed ones do.

/// Income for period totals. Borrowed money is cash in, but it's a debt.
bool countsAsIncome(TxnType type) => type == TxnType.income;

/// Spending for period totals and budgets. Lending money out is cash out,
/// but it's still yours (a receivable).
bool countsAsExpense(TxnType type) => type == TxnType.expense;

/// Contribution to period spending: expenses add, refunds take away
/// (rule 9 — a refund is never income).
int spendingEffect(TxnType type, int amountPaise) => switch (type) {
  TxnType.expense => amountPaise,
  TxnType.refund => -amountPaise,
  _ => 0,
};

/// Signed effect of a transaction on its account's balance, in paise.
int txnBalanceEffect(TxnType type, int amountPaise) => switch (type) {
  TxnType.expense || TxnType.lent => -amountPaise,
  TxnType.income || TxnType.borrowed || TxnType.refund => amountPaise,
};

/// Net worth = what you own − what you owe. Every input is in paise and
/// already non-negative.
class NetWorth {
  /// Account balances (investments at their recorded current value).
  final int accounts;

  /// Money lent out and not yet repaid.
  final int receivables;

  /// Money borrowed from people and not yet repaid.
  final int borrowed;

  /// Principal still owed on loans and EMIs.
  final int loans;

  /// Owed on credit cards: unpaid statements and unbilled spending
  /// (rule 11).
  final int cards;

  const NetWorth({
    required this.accounts,
    required this.receivables,
    required this.borrowed,
    required this.loans,
    this.cards = 0,
  });

  int get assets => accounts + receivables;
  int get liabilities => borrowed + loans + cards;
  int get total => assets - liabilities;
}

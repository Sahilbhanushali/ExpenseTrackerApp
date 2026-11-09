/// Credit card statement arithmetic. Pure — no database, no Flutter.
///
/// The statement the user enters is the truth for what's due; the app's
/// own figure is shown beside it, never forced to match (reconciliation).
library;

import 'salary_cycle.dart';

/// What the user copied from the statement. All paise.
class StatementFigures {
  final int previousBalance;
  final int payments;
  final int refunds;
  final int purchases;
  final int emiInstallments;

  /// Interest, late fees, GST and other charges.
  final int charges;
  final int totalDue;
  final int minimumDue;

  const StatementFigures({
    this.previousBalance = 0,
    this.payments = 0,
    this.refunds = 0,
    this.purchases = 0,
    this.emiInstallments = 0,
    this.charges = 0,
    required this.totalDue,
    this.minimumDue = 0,
  });

  /// The statement's own arithmetic. Banks differ on what they itemise, so
  /// a mismatch with [totalDue] is shown, not "fixed".
  int get computedDue =>
      previousBalance -
      payments -
      refunds +
      purchases +
      emiInstallments +
      charges;

  int get difference => totalDue - computedDue;
}

enum StatementState { paid, partlyPaid, unpaid, overdue }

String statementStateLabel(StatementState s) => switch (s) {
  StatementState.paid => 'Paid',
  StatementState.partlyPaid => 'Partly paid',
  StatementState.unpaid => 'Due',
  StatementState.overdue => 'Overdue',
};

/// Where a statement stands after [paid] has gone toward it.
class StatementStanding {
  final int totalDue;
  final int minimumDue;
  final int paid;
  final DateTime dueDate;
  final DateTime today;

  const StatementStanding({
    required this.totalDue,
    required this.minimumDue,
    required this.paid,
    required this.dueDate,
    required this.today,
  });

  /// Still unpaid statements remain a liability (rule 11).
  int get remaining => (totalDue - paid).clamp(0, totalDue);
  int get minimumRemaining => (minimumDue - paid).clamp(0, minimumDue);

  StatementState get state {
    if (remaining == 0) return StatementState.paid;
    if (dateOnly(today).isAfter(dateOnly(dueDate))) {
      return StatementState.overdue;
    }
    return paid > 0 ? StatementState.partlyPaid : StatementState.unpaid;
  }

  /// Days until the due date (negative once past it).
  int get daysToDue => dateOnly(dueDate).difference(dateOnly(today)).inDays;

  /// Anything left after the due date revolves and attracts interest —
  /// allocation puts it ahead of discretionary spending and investing.
  bool get revolving => remaining > 0 && daysToDue < 0;
}

/// Utilisation of a credit limit, 0–100+.
int utilisation(int outstanding, int limit) =>
    limit <= 0 ? 0 : (outstanding * 100 / limit).round();

/// A card EMI's remaining payable is a fact (installment × installments
/// left); its principal outstanding is only known when the bank gave a
/// principal figure.
class CardEmiStanding {
  final int installment;
  final int tenure;
  final int billed;

  /// Principal billed so far, when the statements itemised it.
  final int? principalBilled;
  final int purchaseAmount;

  const CardEmiStanding({
    required this.installment,
    required this.tenure,
    required this.billed,
    required this.purchaseAmount,
    this.principalBilled,
  });

  int get remainingInstallments => (tenure - billed).clamp(0, tenure);
  int get remainingPayable => installment * remainingInstallments;

  /// Null when the bank hasn't said how much of each installment was
  /// principal — the app won't invent it.
  int? get principalOutstanding => principalBilled == null
      ? null
      : (purchaseAmount - principalBilled!).clamp(0, purchaseAmount);
  bool get finished => remainingInstallments == 0;
}

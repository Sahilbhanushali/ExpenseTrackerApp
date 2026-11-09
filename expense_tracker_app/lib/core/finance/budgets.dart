/// Budget periods and thresholds. Pure — no database, no Flutter.
///
/// A budget caps spending (expenses net of refunds) over one period. Limits
/// are only ever changed by the user: extra income never raises them.
library;

import 'salary_cycle.dart';

enum BudgetPeriod { cycle, month, week, day, custom }

String budgetPeriodLabel(BudgetPeriod p) => switch (p) {
  BudgetPeriod.cycle => 'Salary cycle',
  BudgetPeriod.month => 'Month',
  BudgetPeriod.week => 'Week',
  BudgetPeriod.day => 'Day',
  BudgetPeriod.custom => 'Custom',
};

BudgetPeriod budgetPeriodFrom(String v) => BudgetPeriod.values.firstWhere(
  (p) => p.name == v,
  orElse: () => BudgetPeriod.month,
);

class Budget {
  final int? id;
  final BudgetPeriod period;

  /// Null caps all spending in the period.
  final String? category;

  /// In paise.
  final int limitPaise;

  /// Custom budgets only.
  final DateTime? start;
  final DateTime? end;

  /// Caution from this share of the limit (1–99).
  final int cautionPct;

  /// Needs, not wants — Smart Money Allocation funds these first.
  final bool essential;
  final String? name;

  const Budget({
    this.id,
    required this.period,
    this.category,
    required this.limitPaise,
    this.start,
    this.end,
    this.cautionPct = 80,
    this.essential = false,
    this.name,
  });

  bool get isOverall => category == null;

  String get label =>
      name ??
      (category == null
          ? 'All spending'
          : '${category![0].toUpperCase()}${category!.substring(1)}');
}

/// An inclusive date range.
class PeriodRange {
  final DateTime start;
  final DateTime end;
  const PeriodRange(this.start, this.end);

  int get days => end.difference(start).inDays + 1;

  /// Days from [today] to [end], counting today; 0 once it's over.
  int daysLeft(DateTime today) {
    final t = dateOnly(today);
    if (t.isAfter(end)) return 0;
    return end.difference(t.isBefore(start) ? start : t).inDays + 1;
  }
}

/// The period of [b] that contains [today]. Weeks run Monday to Sunday.
/// A cycle budget runs from the open cycle's start to the latest expected
/// salary day (the day its money must last until). Null when there's no
/// cycle yet, or for a custom budget without dates.
PeriodRange? currentPeriod(
  Budget b,
  DateTime today, {
  CycleRange? cycle,
  SalaryProfile profile = const SalaryProfile(),
}) {
  final t = dateOnly(today);
  switch (b.period) {
    case BudgetPeriod.day:
      return PeriodRange(t, t);
    case BudgetPeriod.week:
      final monday = t.subtract(Duration(days: t.weekday - 1));
      return PeriodRange(monday, monday.add(const Duration(days: 6)));
    case BudgetPeriod.month:
      return PeriodRange(
        DateTime(t.year, t.month, 1),
        DateTime(t.year, t.month + 1, 0),
      );
    case BudgetPeriod.cycle:
      if (cycle == null) return null;
      final end = cycle.end ?? nextSalaryWindow(cycle.start, profile).latest;
      // Salary is late: the period stretches to today.
      return PeriodRange(cycle.start, end.isBefore(t) ? t : end);
    case BudgetPeriod.custom:
      final s = b.start, e = b.end;
      if (s == null || e == null) return null;
      return PeriodRange(dateOnly(s), dateOnly(e));
  }
}

/// Ordered by severity. The same rules as everywhere else in the app:
/// caution from the budget's percentage, reached at exactly 100%, exceeded
/// above it.
enum BudgetLevel { ok, caution, reached, exceeded }

BudgetLevel budgetLevel(int spent, int limit, int cautionPct) {
  if (limit <= 0) return BudgetLevel.ok;
  if (spent > limit) return BudgetLevel.exceeded;
  if (spent == limit) return BudgetLevel.reached;
  if (spent * 100 >= limit * cautionPct) return BudgetLevel.caution;
  return BudgetLevel.ok;
}

class BudgetUsage {
  final Budget budget;
  final PeriodRange range;

  /// Net of refunds, in paise. Can be negative if more came back than went
  /// out in the period.
  final int spent;
  final int daysLeft;

  const BudgetUsage({
    required this.budget,
    required this.range,
    required this.spent,
    required this.daysLeft,
  });

  int get limit => budget.limitPaise;
  int get remaining => limit - spent;
  int get percent => limit > 0 ? (spent * 100 / limit).floor() : 0;
  BudgetLevel get level => budgetLevel(spent, limit, budget.cautionPct);

  /// What can still be spent per day to stay inside the limit.
  int? get perDayLeft =>
      remaining > 0 && daysLeft > 0 ? remaining ~/ daysLeft : null;
}

/// Cycle budgets are planned against income actually received this cycle.
/// Positive: income not yet given a budget. Negative: budgets promise more
/// than came in.
int cycleBudgetGap(int cycleIncome, Iterable<Budget> cycleBudgets) {
  final categories = cycleBudgets.where((b) => !b.isOverall);
  final overall = cycleBudgets.where((b) => b.isOverall).firstOrNull;
  final planned =
      overall?.limitPaise ??
      categories.fold<int>(0, (s, b) => s + b.limitPaise);
  return cycleIncome - planned;
}

/// Why a budget can't be saved, or null.
String? validateBudget(Budget b, Iterable<Budget> existing) {
  if (b.limitPaise <= 0) return 'Enter a limit greater than zero.';
  if (b.cautionPct < 1 || b.cautionPct > 99) {
    return 'The caution level must be between 1% and 99%.';
  }
  if (b.period == BudgetPeriod.custom) {
    if (b.start == null || b.end == null) {
      return 'Pick the start and end dates.';
    }
    if (b.end!.isBefore(b.start!)) return 'The end date is before the start.';
  } else if (existing.any(
    // A budget without an id is new, so any match is a duplicate.
    (o) =>
        (b.id == null || o.id != b.id) &&
        o.period == b.period &&
        o.category == b.category,
  )) {
    return 'There is already a ${budgetPeriodLabel(b.period).toLowerCase()} '
        'budget for ${b.label.toLowerCase()}.';
  }
  return null;
}

/// Goals, the emergency fund and manual investments. Pure — no database,
/// no Flutter.
///
/// None of these is a separate pile of money: every rupee lives in an
/// account and is counted once there (net worth). A goal is an earmark on
/// a savings account; the emergency fund is the balance of emergency
/// accounts; holdings describe what an investment account's money is in.
/// Savings and investing are never spending (rules 5–7).
library;

import 'budgets.dart';
import 'salary_cycle.dart';

/// Whole months from [from] to [to], at least 1 while [to] is ahead.
int monthsBetween(DateTime from, DateTime to) {
  final a = dateOnly(from), b = dateOnly(to);
  if (!b.isAfter(a)) return 0;
  var m = (b.year - a.year) * 12 + b.month - a.month;
  if (b.day < a.day) m -= 1;
  return m < 1 ? 1 : m;
}

enum GoalHorizon { short, long }

class GoalProgress {
  /// All paise.
  final int target;
  final int saved;
  final DateTime? targetDate;
  final int? monthlyContribution;

  const GoalProgress({
    required this.target,
    required this.saved,
    this.targetDate,
    this.monthlyContribution,
  });

  int get remaining => (target - saved).clamp(0, target);
  int get percent =>
      target <= 0 ? 0 : (saved * 100 / target).floor().clamp(0, 100);
  bool get reached => remaining == 0;

  /// What it takes per month to finish by [targetDate]; null without one.
  int? requiredMonthly(DateTime today) {
    final d = targetDate;
    if (d == null || reached) return null;
    final m = monthsBetween(today, d);
    return m == 0 ? remaining : (remaining / m).ceil();
  }

  /// On track when the planned contribution meets what the date needs.
  bool? onTrack(DateTime today) {
    final need = requiredMonthly(today);
    final plan = monthlyContribution;
    if (need == null || plan == null) return null;
    return plan >= need;
  }

  /// What allocation should ask for this period: the planned contribution,
  /// else what the date needs; never more than is left.
  int? suggested(DateTime today) {
    if (reached) return null;
    final v = monthlyContribution ?? requiredMonthly(today);
    if (v == null) return null;
    return v < remaining ? v : remaining;
  }
}

/// A budget limit expressed per month.
int monthlyEquivalent(Budget b) => switch (b.period) {
  BudgetPeriod.month || BudgetPeriod.cycle => b.limitPaise,
  BudgetPeriod.week => (b.limitPaise * 52 / 12).round(),
  BudgetPeriod.day => (b.limitPaise * 365 / 12).round(),
  BudgetPeriod.custom => 0,
};

enum EssentialSource { override, budgets, spending, none }

/// Essential spending per month, and where the figure came from.
({int amount, EssentialSource source}) essentialMonthly({
  int? override,
  required Iterable<Budget> budgets,
  required int averageEssentialSpending,
}) {
  if (override != null && override > 0) {
    return (amount: override, source: EssentialSource.override);
  }
  final fromBudgets = budgets
      .where((b) => b.essential && b.category != null)
      .fold<int>(0, (s, b) => s + monthlyEquivalent(b));
  if (fromBudgets > 0) {
    return (amount: fromBudgets, source: EssentialSource.budgets);
  }
  if (averageEssentialSpending > 0) {
    return (amount: averageEssentialSpending, source: EssentialSource.spending);
  }
  return (amount: 0, source: EssentialSource.none);
}

class EmergencyStatus {
  /// All paise. [current] is the emergency accounts' balance — the same
  /// money that's in net worth, not an extra asset.
  final int current;
  final int target;
  final int essentialMonthly;
  final int? monthlyContribution;

  const EmergencyStatus({
    required this.current,
    required this.target,
    required this.essentialMonthly,
    this.monthlyContribution,
  });

  int get shortfall => (target - current).clamp(0, target);
  int get percent =>
      target <= 0 ? 0 : (current * 100 / target).floor().clamp(0, 100);

  /// How many months of essentials it would cover.
  double? get coverageMonths =>
      essentialMonthly <= 0 ? null : current / essentialMonthly;

  /// The planned contribution, or a twelfth of the gap; never beyond it.
  int get suggestedContribution {
    if (shortfall == 0) return 0;
    final v = monthlyContribution ?? (shortfall / 12).ceil();
    return v < shortfall ? v : shortfall;
  }
}

/// The target: [months] × essential monthly, or a custom [amount].
int emergencyTarget({int? months, int? amount, required int essentialMonthly}) {
  if (months != null && months > 0) return months * essentialMonthly;
  return amount ?? 0;
}

/// An investment account seen through its holdings. All paise.
class InvestmentStanding {
  /// Money moved into the account (its balance).
  final int balance;
  final int invested;

  /// The user's own latest figure for the holdings — not a live price.
  final int currentValue;
  final int holdings;

  const InvestmentStanding({
    required this.balance,
    required this.invested,
    required this.currentValue,
    required this.holdings,
  });

  /// Cash in the account not yet put into a holding.
  int get uninvested =>
      (balance - invested).clamp(0, balance < 0 ? 0 : balance);

  /// What the account is worth: uninvested cash plus the holdings' value.
  int get worth => uninvested + currentValue;

  /// On paper, as of the values entered — never a promise.
  int get gain => currentValue - invested;
}

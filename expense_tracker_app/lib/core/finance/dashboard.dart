/// Dashboard figures: financial position, debt overview, comparable periods
/// and plain-language insights. Pure — no database, no Flutter.
library;

import '../../data/models/account.dart';
import '../constants/calendar.dart';
import '../utils/money_formatter.dart';
import 'accounting.dart';
import 'budgets.dart';
import 'calendar_events.dart';
import 'salary_cycle.dart';

/// Where an account's money belongs on the dashboard. Every account is in
/// exactly one group, so nothing is counted twice.
enum AccountGroup { spending, savings, emergency, investing }

AccountGroup accountGroup(MoneyAccount a) {
  if (a.type == AccountType.investment ||
      a.roles.contains(AccountRole.investment)) {
    return AccountGroup.investing;
  }
  if (a.type == AccountType.emergencyFund ||
      a.roles.contains(AccountRole.emergency)) {
    return AccountGroup.emergency;
  }
  if (a.roles.contains(AccountRole.savings)) return AccountGroup.savings;
  return AccountGroup.spending;
}

/// Actual vs reserved vs available, and what makes up net worth. Paise.
class FinancialPosition {
  /// Actual balance of active spending accounts (bank, wallet, cash).
  final int inAccounts;
  final int onHold;

  /// Approved allocations still sitting in that cash.
  final int reserved;

  /// Spending accounts at their worth, closed ones included (net worth).
  final int cash;
  final int savings;
  final int emergency;
  final int investments;
  final int receivables;
  final int borrowed;
  final int loans;
  final int cards;

  const FinancialPosition({
    required this.inAccounts,
    required this.onHold,
    required this.reserved,
    required this.cash,
    required this.savings,
    required this.emergency,
    required this.investments,
    this.receivables = 0,
    this.borrowed = 0,
    this.loans = 0,
    this.cards = 0,
  });

  factory FinancialPosition.from(
    Iterable<({MoneyAccount account, int balance, int worth})> accounts, {
    int reserved = 0,
    int receivables = 0,
    int borrowed = 0,
    int loans = 0,
    int cards = 0,
  }) {
    var inAccounts = 0, hold = 0;
    final byGroup = {for (final g in AccountGroup.values) g: 0};
    for (final a in accounts) {
      final g = accountGroup(a.account);
      byGroup[g] = byGroup[g]! + a.worth;
      if (a.account.isSpendable) {
        inAccounts += a.balance;
        hold += a.account.holdPaise;
      }
    }
    return FinancialPosition(
      inAccounts: inAccounts,
      onHold: hold,
      reserved: reserved,
      cash: byGroup[AccountGroup.spending]!,
      savings: byGroup[AccountGroup.savings]!,
      emergency: byGroup[AccountGroup.emergency]!,
      investments: byGroup[AccountGroup.investing]!,
      receivables: receivables,
      borrowed: borrowed,
      loans: loans,
      cards: cards,
    );
  }

  /// Same figure Smart allocation works from.
  int get available => inAccounts - onHold - reserved;
  int get debt => borrowed + loans + cards;

  NetWorth get netWorth => NetWorth(
    accounts: cash + savings + emergency + investments,
    receivables: receivables,
    borrowed: borrowed,
    loans: loans,
    cards: cards,
  );
}

class DebtOverview {
  final int cards;
  final int loans;
  final int borrowed;
  final FinEvent? nextCardDue;
  final FinEvent? nextStatement;
  final FinEvent? nextEmi;
  final List<FinEvent> overdue;

  const DebtOverview({
    this.cards = 0,
    this.loans = 0,
    this.borrowed = 0,
    this.nextCardDue,
    this.nextStatement,
    this.nextEmi,
    this.overdue = const [],
  });

  int get total => cards + loans + borrowed;
  int get overdueTotal => overdue.fold(0, (s, e) => s + (e.amount ?? 0));
  bool get isEmpty =>
      total == 0 && overdue.isEmpty && nextCardDue == null && nextEmi == null;
}

DebtOverview debtOverview(
  Iterable<FinEvent> events,
  DateTime today, {
  int cards = 0,
  int loans = 0,
  int borrowed = 0,
}) {
  final sorted = events.toList()..sort((a, b) => a.date.compareTo(b.date));
  FinEvent? next(EventKind k) => sorted
      .where((e) => e.kind == k && !e.overdue(today))
      .where((e) => !dateOnly(e.date).isBefore(dateOnly(today)))
      .firstOrNull;
  return DebtOverview(
    cards: cards,
    loans: loans,
    borrowed: borrowed,
    nextCardDue: next(EventKind.cardDue),
    nextStatement: next(EventKind.statement),
    nextEmi: next(EventKind.emi),
    overdue: [
      for (final e in sorted)
        if (e.overdue(today) &&
            (e.kind == EventKind.emi ||
                e.kind == EventKind.cardDue ||
                e.kind == EventKind.bill))
          e,
    ],
  );
}

/// Outgoing obligations due on or before [until], overdue ones included.
int dueBy(Iterable<FinEvent> events, DateTime today, DateTime until) =>
    windowTotals(eventsBetween(events, today, until, today)).outgoing;

/// The matching stretch of the previous period: the same number of days
/// from [previousStart] (or straight before [from]), never past [from].
/// "This point last month" for a month, the same for a cycle.
({DateTime from, DateTime to}) comparablePeriod(
  DateTime from,
  DateTime to, {
  DateTime? previousStart,
}) {
  final f = dateOnly(from), t = dateOnly(to);
  final days = t.difference(f).inDays;
  final prevEnd = DateTime(f.year, f.month, f.day - 1);
  final start = previousStart != null
      ? dateOnly(previousStart)
      : DateTime(prevEnd.year, prevEnd.month, prevEnd.day - days);
  final end = DateTime(start.year, start.month, start.day + days);
  return (from: start, to: end.isAfter(prevEnd) ? prevEnd : end);
}

enum InsightTone { alert, warning, info, good }

class Insight {
  /// Stable per rule, for keys and tests.
  final String id;
  final InsightTone tone;
  final String title;
  final String detail;
  const Insight(this.id, this.tone, this.title, this.detail);
}

/// What insights are drawn from. Paise. [current] is false for a past
/// period: then only that period's own figures are used.
class InsightInput {
  /// "month", "cycle" or "period" — used in sentences.
  final String period;
  final String currency;
  final bool current;
  final int spent;
  final int income;
  final int previousSpent;
  final Map<String, int> categories;
  final Map<String, int> previousCategories;
  final int movedToSavings;
  final List<BudgetUsage> budgets;
  final List<FinEvent> overdue;
  final int criticalShortfall;
  final bool salaryLate;
  final int emergencyTarget;
  final double? emergencyCoverage;

  const InsightInput({
    required this.period,
    required this.currency,
    this.current = true,
    required this.spent,
    required this.income,
    this.previousSpent = 0,
    this.categories = const {},
    this.previousCategories = const {},
    this.movedToSavings = 0,
    this.budgets = const [],
    this.overdue = const [],
    this.criticalShortfall = 0,
    this.salaryLate = false,
    this.emergencyTarget = 0,
    this.emergencyCoverage,
  });
}

/// Changes smaller than this are noise, not insight.
const _minChange = 50000; // ₹500
const _paceThresholdPct = 15;

/// Plain-language observations, most urgent first. Every figure in the text
/// comes from the input; nothing is predicted.
List<Insight> insightsFor(InsightInput i) {
  String m(int v) => formatMoney(v, i.currency);
  final out = <Insight>[];
  final p = i.period;

  if (i.current && i.overdue.isNotEmpty) {
    final total = i.overdue.fold(0, (s, e) => s + (e.amount ?? 0));
    final first = i.overdue.first;
    final n = i.overdue.length;
    out.add(
      Insight(
        'overdue',
        InsightTone.alert,
        '$n payment${n == 1 ? '' : 's'} overdue',
        '${m(total)} in total. ${first.title} was due ${first.date.day} ${kMonthNamesShort[first.date.month - 1]}.',
      ),
    );
  }
  if (i.current && i.criticalShortfall > 0) {
    out.add(
      Insight(
        'shortfall',
        InsightTone.alert,
        '${m(i.criticalShortfall)} short before payday',
        'Essentials and dues before your next salary aren’t covered. '
            'Smart allocation shows which.',
      ),
    );
  }
  if (i.current && i.salaryLate) {
    out.add(
      const Insight(
        'salary-late',
        InsightTone.warning,
        'Salary is later than expected',
        'Plans don’t count it until you record it.',
      ),
    );
  }

  if (i.current) {
    String name(BudgetUsage u) => u.budget.category ?? 'Overall';
    final over = i.budgets
        .where((u) => u.level == BudgetLevel.exceeded)
        .toList();
    if (over.isNotEmpty) {
      final by = over.fold(0, (s, u) => s + (u.spent - u.limit));
      out.add(
        Insight(
          'over-budget',
          InsightTone.warning,
          'Over budget: ${over.map(name).join(', ')}',
          'By ${m(by)} in total.',
        ),
      );
    }
    final near = i.budgets
        .where(
          (u) =>
              u.level == BudgetLevel.caution || u.level == BudgetLevel.reached,
        )
        .toList();
    if (near.isNotEmpty) {
      out.add(
        Insight(
          'near-budget',
          InsightTone.info,
          'Close to the limit: ${near.map((u) => '${name(u)} (${u.percent}%)').join(', ')}',
          '${m(near.fold(0, (s, u) => s + (u.remaining > 0 ? u.remaining : 0)))} left across '
              '${near.length == 1 ? 'it' : 'them'}.',
        ),
      );
    }
  }

  if (i.previousSpent > 0 && (i.spent - i.previousSpent).abs() >= _minChange) {
    final pct = ((i.spent - i.previousSpent) * 100 / i.previousSpent).round();
    if (pct.abs() >= _paceThresholdPct) {
      final up = pct > 0;
      out.add(
        Insight(
          up ? 'pace-up' : 'pace-down',
          up ? InsightTone.warning : InsightTone.good,
          'Spending is ${up ? 'up' : 'down'} ${pct.abs()}% on last $p',
          '${m(i.spent)} so far vs ${m(i.previousSpent)} by this point last $p.',
        ),
      );
    }
  }

  MapEntry<String, int>? jump;
  for (final e in i.categories.entries) {
    final before = i.previousCategories[e.key] ?? 0;
    final diff = e.value - before;
    if (diff < _minChange || (before > 0 && e.value * 2 < before * 3)) {
      continue;
    }
    if (jump == null || diff > jump.value) jump = MapEntry(e.key, diff);
  }
  if (jump != null) {
    final before = i.previousCategories[jump.key] ?? 0;
    out.add(
      Insight(
        'category-jump',
        InsightTone.info,
        '${_titleCase(jump.key)}: ${m(jump.value)} more than last $p',
        '${m(i.categories[jump.key]!)} vs ${m(before)} by the same point.',
      ),
    );
  }

  if (i.income > 0 && i.spent > i.income) {
    out.add(
      Insight(
        'overspent',
        InsightTone.warning,
        'Spent ${m(i.spent - i.income)} more than this $p’s income',
        'The gap came out of money you already had.',
      ),
    );
  } else if (i.income > 0) {
    final kept = ((i.income - i.spent) * 100 / i.income).floor();
    if (kept >= 20) {
      out.add(
        Insight(
          'kept',
          InsightTone.good,
          'You’ve kept $kept% of this $p’s income',
          '${m(i.income - i.spent)} not spent so far — before bills still due.',
        ),
      );
    }
  }
  if (i.movedToSavings > 0) {
    out.add(
      Insight(
        'saved',
        InsightTone.good,
        '${m(i.movedToSavings)} moved to savings this $p',
        'Into savings, emergency and investment accounts. Not spending.',
      ),
    );
  }

  if (i.current && i.emergencyTarget > 0) {
    final c = i.emergencyCoverage;
    if (c != null && c < 1) {
      out.add(
        Insight(
          'emergency-low',
          InsightTone.warning,
          'Emergency fund covers under a month',
          'About ${c.toStringAsFixed(1)} months of essentials so far.',
        ),
      );
    }
  }

  // Stable sort: most urgent first, rule order within a tone.
  final indexed = out.indexed.toList()
    ..sort((a, b) {
      final t = a.$2.tone.index.compareTo(b.$2.tone.index);
      return t != 0 ? t : a.$1.compareTo(b.$1);
    });
  return [for (final (_, x) in indexed) x];
}

String _titleCase(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

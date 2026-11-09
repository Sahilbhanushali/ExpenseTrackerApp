import 'package:flutter/foundation.dart';

import '../../core/finance/budgets.dart';
import '../../core/utils/money_formatter.dart';
import '../../data/repositories/budget_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../cycles/cycle_controller.dart';
import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';

/// Every budget with its spending for the period containing today.
class BudgetController extends ChangeNotifier {
  final BudgetRepository _repo;
  final TransactionRepository _txns;
  BudgetController({BudgetRepository? repo, TransactionRepository? txnRepo})
    : _repo = repo ?? BudgetRepository(),
      _txns = txnRepo ?? TransactionRepository();

  ExpensesController? _expenses;
  CycleController? _cycles;

  List<Budget> _budgets = [];
  List<Budget> get budgets => _budgets;

  List<BudgetUsage> _usages = [];

  /// Current-period usage for each budget that has a period right now
  /// (a cycle budget needs a cycle).
  List<BudgetUsage> get usages => _usages;

  void attach(ExpensesController expenses, CycleController cycles) {
    _expenses?.removeListener(refresh);
    _cycles?.removeListener(refresh);
    _expenses = expenses..addListener(refresh);
    _cycles = cycles..addListener(refresh);
  }

  /// Imports the old month-only budgets from config the first time.
  Future<void> init(SettingsController settings) async {
    final config = settings.config;
    if (!config.budgetsImported) {
      await _repo.importLegacy(config.monthlyBudgetPaise, config.budgets);
      await settings.markBudgetsImported();
    }
    await refresh();
  }

  Future<void> refresh({DateTime? today}) async {
    final now = today ?? DateTime.now();
    _budgets = await _repo.list();
    final cycle = _cycles?.cycles.lastOrNull;
    final profile = _cycles?.profile;

    // One totals query per distinct date range, not one per budget.
    final totals = <String, Future<(int, Map<String, int>)>>{};
    Future<(int, Map<String, int>)> spendIn(PeriodRange r) =>
        totals.putIfAbsent('${r.start}|${r.end}', () async {
          final (t, c) = await (
            _txns.totalsRange(r.start, r.end),
            _txns.categoryTotalsRange(r.start, r.end),
          ).wait;
          return (t.expense, c);
        });

    final usages = <BudgetUsage>[];
    for (final b in _budgets) {
      final range = profile == null
          ? currentPeriod(b, now, cycle: cycle)
          : currentPeriod(b, now, cycle: cycle, profile: profile);
      if (range == null) continue;
      final (all, byCategory) = await spendIn(range);
      usages.add(
        BudgetUsage(
          budget: b,
          range: range,
          spent: b.category == null ? all : (byCategory[b.category] ?? 0),
          daysLeft: range.daysLeft(now),
        ),
      );
    }
    _usages = usages;
    notifyListeners();
  }

  Budget? _find(BudgetPeriod p, [String? category]) => _budgets
      .where((b) => b.period == p && b.category == category)
      .firstOrNull;

  /// The calendar-month overall budget, in paise (0 when none) — what the
  /// month views and the Spending Guardian compare against.
  int get monthOverall => _find(BudgetPeriod.month)?.limitPaise ?? 0;

  /// Calendar-month caps per category, in paise.
  Map<String, int> get monthCategoryCaps => {
    for (final b in _budgets)
      if (b.period == BudgetPeriod.month && b.category != null)
        b.category!: b.limitPaise,
  };

  /// Budget id → level, to compare before and after a new expense.
  Map<int, BudgetLevel> levels() => {
    for (final u in _usages) u.budget.id!: u.level,
  };

  /// One line per budget whose level went up since [before] — for the
  /// snackbar after logging an expense.
  List<String> crossedSince(Map<int, BudgetLevel> before, String currency) => [
    for (final u in _usages)
      if (u.level.index > (before[u.budget.id] ?? BudgetLevel.ok).index &&
          u.level != BudgetLevel.ok)
        _crossedLine(u, currency),
  ];

  static String _crossedLine(BudgetUsage u, String currency) {
    final name =
        '${u.budget.label} (${budgetPeriodLabel(u.budget.period).toLowerCase()})';
    return switch (u.level) {
      BudgetLevel.exceeded =>
        '$name budget exceeded by ${formatMoney(-u.remaining, currency)}.',
      BudgetLevel.reached => '$name budget fully used.',
      _ =>
        '$name: ${u.percent}% used, ${formatMoney(u.remaining, currency)} left.',
    };
  }

  /// Throws [BudgetException] with a message for the user.
  Future<void> save(Budget b) async {
    await _repo.save(b);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _repo.remove(id);
    await refresh();
  }

  @override
  void dispose() {
    _expenses?.removeListener(refresh);
    _cycles?.removeListener(refresh);
    super.dispose();
  }
}

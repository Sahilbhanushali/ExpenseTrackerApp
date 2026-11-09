import 'package:flutter/foundation.dart';

import '../../core/finance/dashboard.dart';
import '../../core/finance/salary_cycle.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/allocation_repository.dart';
import '../../data/repositories/net_worth_repository.dart';
import '../accounts/accounts_controller.dart';
import '../allocation/allocation_controller.dart';
import '../budgets/budget_controller.dart';
import '../calendar/calendar_controller.dart';
import '../cards/cards_controller.dart';
import '../cycles/cycle_controller.dart';
import '../emergency/emergency_controller.dart';
import '../expenses/expenses_controller.dart';
import '../lending/lending_controller.dart';
import '../loans/loans_controller.dart';
import '../settings/settings_controller.dart';

/// Derived dashboard state: financial position, debt overview, net worth
/// trend and insights. Reads what the other controllers already hold;
/// recomputes only when one of them changes, never inside build().
class DashboardController extends ChangeNotifier {
  final NetWorthRepository _snapshots;

  /// Off in tests that don't want a database write per change.
  final bool recordSnapshots;

  DashboardController({
    NetWorthRepository? snapshots,
    this.recordSnapshots = true,
  }) : _snapshots = snapshots ?? NetWorthRepository();

  late AccountsController _accounts;
  late LendingController _lending;
  late LoansController _loans;
  late CardsController _cards;
  late AllocationController _allocation;
  late CalendarController _calendar;
  late CycleController _cycles;
  late EmergencyController _emergency;
  late BudgetController _budgets;
  late ExpensesController _expenses;
  late SettingsController _settings;
  final List<Listenable> _sources = [];
  bool _attached = false;

  /// False until wired to the other controllers (e.g. in layout tests).
  bool get ready => _attached;

  FinancialPosition _position = const FinancialPosition(
    inAccounts: 0,
    onHold: 0,
    reserved: 0,
    cash: 0,
    savings: 0,
    emergency: 0,
    investments: 0,
  );
  FinancialPosition get position => _position;

  DebtOverview _debt = const DebtOverview();
  DebtOverview get debt => _debt;

  List<NetWorthPoint> _trend = [];
  List<NetWorthPoint> get trend => _trend;

  void attach({
    required AccountsController accounts,
    required LendingController lending,
    required LoansController loans,
    required CardsController cards,
    required AllocationController allocation,
    required CalendarController calendar,
    required CycleController cycles,
    required EmergencyController emergency,
    required BudgetController budgets,
    required ExpensesController expenses,
    required SettingsController settings,
  }) {
    for (final s in _sources) {
      s.removeListener(_recompute);
    }
    _accounts = accounts;
    _lending = lending;
    _loans = loans;
    _cards = cards;
    _allocation = allocation;
    _calendar = calendar;
    _cycles = cycles;
    _emergency = emergency;
    _budgets = budgets;
    _expenses = expenses;
    _settings = settings;
    _attached = true;
    // Everything the position and debt figures read.
    _sources
      ..clear()
      ..addAll([accounts, lending, loans, cards, allocation, calendar]);
    for (final s in _sources) {
      s.addListener(_recompute);
    }
  }

  @override
  void dispose() {
    for (final s in _sources) {
      s.removeListener(_recompute);
    }
    super.dispose();
  }

  Future<void> refresh() async {
    _recompute();
    if (recordSnapshots) _trend = await _snapshots.history(12);
    notifyListeners();
  }

  int _sumLending(TxnType type) => _lending.outstanding
      .where((t) => t.type == type)
      .fold(0, (s, t) => s + t.amountPaise);

  void _recompute() {
    if (!_attached) return;
    _position = FinancialPosition.from(
      [
        for (final a in _accounts.accounts)
          (account: a.account, balance: a.balance, worth: a.worth),
      ],
      reserved: _allocation.view?.reserved ?? 0,
      receivables: _sumLending(TxnType.lent),
      borrowed: _sumLending(TxnType.borrowed),
      loans: _loans.outstanding,
      cards: _cards.outstanding,
    );
    _debt = debtOverview(
      _calendar.events,
      DateTime.now(),
      cards: _position.cards,
      loans: _position.loans,
      borrowed: _position.borrowed,
    );
    notifyListeners();
    _record();
  }

  int? _recorded;
  Future<void> _record() async {
    if (!recordSnapshots) return;
    final nw = _position.netWorth;
    if (_recorded == nw.total) return;
    _recorded = nw.total;
    try {
      await _snapshots.record(
        DateTime.now(),
        assets: nw.assets,
        liabilities: nw.liabilities,
      );
      _trend = await _snapshots.history(12);
      notifyListeners();
    } catch (e) {
      debugPrint('Net worth snapshot failed: ${e.runtimeType}');
    }
  }

  /// The current cycle's plan: approved so far, unallocated cash now, and
  /// what's still due before the next salary.
  ({int allocated, int unallocated, int dueBeforePayday}) cyclePlan({
    DateTime? today,
  }) {
    final t = dateOnly(today ?? DateTime.now());
    final view = _allocation.view;
    final allocated = (view?.decisions ?? const [])
        .where((d) => d.status != DecisionStatus.skipped)
        .fold(0, (s, d) => s + d.amount);
    final horizon =
        view?.snapshot.horizon ??
        _cycles.current?.standing?.window.latest ??
        DateTime(t.year, t.month + 1, 0);
    return (
      allocated: allocated,
      unallocated: _position.available,
      dueBeforePayday: dueBy(_calendar.events, t, horizon),
    );
  }

  /// Insights for [from]..[to], compared with the same stretch of the
  /// period before (starting at [previousStart] when given).
  Future<List<Insight>> insights({
    required DateTime from,
    required DateTime to,
    DateTime? previousStart,
    required String period,
    DateTime? now,
  }) async {
    final today = dateOnly(now ?? DateTime.now());
    final current = !dateOnly(to).isBefore(today) && !from.isAfter(today);
    final end = current ? today : dateOnly(to);
    final prev = comparablePeriod(from, end, previousStart: previousStart);
    final (totals, cats, prevTotals, prevCats, saved) = await (
      _expenses.totalsRange(from, end),
      _expenses.categoryTotalsRange(from, end),
      _expenses.totalsRange(prev.from, prev.to),
      _expenses.categoryTotalsRange(prev.from, prev.to),
      _accounts.transferredIntoSetAside(from, end),
    ).wait;
    final status = _emergency.status;
    return insightsFor(
      InsightInput(
        period: period,
        currency: _settings.config.currency,
        current: current,
        spent: totals.expense,
        income: totals.income,
        previousSpent: prevTotals.expense,
        categories: cats,
        previousCategories: prevCats,
        movedToSavings: saved,
        budgets: _budgets.usages,
        overdue: _debt.overdue,
        criticalShortfall: _allocation.view?.plan.criticalShortfall ?? 0,
        salaryLate: _cycles.current?.standing?.salaryLate ?? false,
        emergencyTarget: status?.target ?? 0,
        emergencyCoverage: status?.coverageMonths,
      ),
    );
  }
}

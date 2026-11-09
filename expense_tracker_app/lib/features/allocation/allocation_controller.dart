import 'package:flutter/foundation.dart';

import '../../core/finance/allocation.dart';
import '../../core/finance/salary_cycle.dart';
import '../../data/models/account.dart';
import '../../data/repositories/allocation_repository.dart';
import '../accounts/accounts_controller.dart';
import '../budgets/budget_controller.dart';
import '../cards/cards_controller.dart';
import '../cycles/cycle_controller.dart';
import '../emergency/emergency_controller.dart';
import '../goals/goals_controller.dart';
import '../loans/loans_controller.dart';
import '../recurring/recurring_controller.dart';
import '../settings/settings_controller.dart';
import 'allocation_needs.dart';

/// The live plan plus the decisions behind it.
class AllocationView {
  final AllocationSnapshot snapshot;
  final AllocationPlan plan;
  final List<AllocationDecision> decisions;

  /// Held back by reservations still sitting in spendable cash.
  final int reserved;
  final String scope;

  /// Needs the user chose not to fund this period.
  final List<AllocationNeed> skipped;

  const AllocationView({
    required this.snapshot,
    required this.plan,
    required this.decisions,
    required this.reserved,
    required this.scope,
    required this.skipped,
  });

  AllocationDecision? decisionFor(String key) =>
      decisions.where((d) => d.key == key).firstOrNull;
}

class AllocationController extends ChangeNotifier {
  final AllocationRepository _repo;
  AllocationController([AllocationRepository? repo])
    : _repo = repo ?? AllocationRepository();

  late AccountsController _accounts;
  late BudgetController _budgets;
  late CardsController _cards;
  late LoansController _loans;
  late RecurringController _recurring;
  late CycleController _cycles;
  late SettingsController _settings;
  GoalsController? _goals;
  EmergencyController? _emergency;
  bool _attached = false;

  AllocationSettings _config = const AllocationSettings();
  AllocationSettings get config => _config;

  AllocationView? _view;
  AllocationView? get view => _view;

  void attach({
    required AccountsController accounts,
    required BudgetController budgets,
    required CardsController cards,
    required LoansController loans,
    required RecurringController recurring,
    required CycleController cycles,
    required SettingsController settings,
    GoalsController? goals,
    EmergencyController? emergency,
  }) {
    _goals = goals?..addListener(refresh);
    _emergency = emergency?..addListener(refresh);
    _accounts = accounts;
    _budgets = budgets;
    _cards = cards;
    _loans = loans;
    _recurring = recurring;
    _cycles = cycles;
    _settings = settings;
    _attached = true;
    for (final c in [accounts, budgets, cards, loans, recurring, cycles]) {
      c.addListener(refresh);
    }
  }

  /// The cycle start (or the month) that decisions belong to.
  String _scope(DateTime today) {
    final c = _cycles.cycles.lastOrNull;
    return c != null
        ? 'cycle:${isoDate(c.start)}'
        : 'month:${today.year}-${today.month}';
  }

  /// Money must last to the latest expected salary day; a week ahead when
  /// salary is late; the month's end with no cycle at all.
  DateTime _horizon(DateTime today) {
    final standing = _cycles.current?.standing;
    if (standing != null) {
      return standing.salaryLate
          ? dateOnly(today).add(const Duration(days: 7))
          : standing.window.latest;
    }
    return DateTime(today.year, today.month + 1, 0);
  }

  Future<void> refresh() async {
    if (!_attached) return;
    final today = DateTime.now();
    _config = await _repo.settings();
    final scope = _scope(today);
    final decisions = await _repo.decisions(scope);
    final snapshot = AllocationSnapshot(
      today: today,
      horizon: _horizon(today),
      currency: _settings.config.currency,
      accounts: _accounts.accounts,
      budgets: _budgets.usages,
      cards: _cards.cards,
      loans: _loans.loans,
      bills: _recurring.bills,
      goals: _goals?.goals ?? const [],
      // A target in months of essentials is resolved by the emergency fund.
      settings: _config.emergencyMonths != null && _emergency?.status != null
          ? AllocationSettings(
              order: _config.order,
              emergencyTarget: _emergency!.status!.target,
              emergencyMonthly: _config.emergencyMonthly,
              savingsPerCycle: _config.savingsPerCycle,
              investPerCycle: _config.investPerCycle,
              emergencyMonths: _config.emergencyMonths,
              essentialMonthly: _config.essentialMonthly,
            )
          : _config,
    );
    final all = buildNeeds(snapshot);
    final skippedKeys = {
      for (final d in decisions)
        if (d.status == DecisionStatus.skipped) d.key,
    };
    final needs = all.where((n) => !skippedKeys.contains(n.key)).toList();
    final r = effectiveReservations(decisions, needs);
    final held = r.heldBack.values.fold(0, (s, v) => s + v);
    _view = AllocationView(
      snapshot: snapshot,
      plan: allocate(
        available: snapshot.liquid - held,
        needs: needs,
        reservedByKey: r.funded,
        order: _config.order,
      ),
      decisions: decisions,
      reserved: held,
      scope: scope,
      skipped: all.where((n) => skippedKeys.contains(n.key)).toList(),
    );
    notifyListeners();
  }

  /// Whether reserving [amount] for [line] needs money moved, and from where.
  /// Set-aside destinations always do; a spendable destination only for the
  /// part it doesn't already hold.
  ({String? from, int transfer}) moveFor(
    AllocationLine line,
    int amount,
    String? destination,
  ) {
    final v = _view;
    if (v == null || destination == null) return (from: null, transfer: 0);
    final source = v.snapshot.sourceAccount;
    if (source == null || source == destination) {
      return (from: null, transfer: 0);
    }
    final dest = v.snapshot.accounts
        .where((a) => a.account.name == destination)
        .firstOrNull;
    if (dest == null) return (from: null, transfer: 0);
    if (!dest.account.isSpendable) return (from: source, transfer: amount);
    final has = dest.balance - dest.account.holdPaise;
    final missing = amount - (has > 0 ? has : 0);
    return missing > 0
        ? (from: source, transfer: missing)
        : (from: null, transfer: 0);
  }

  /// Approve one line (optionally with an edited amount or destination).
  /// Throws [AllocationException].
  Future<void> approve(
    AllocationLine line, {
    int? amount,
    String? destination,
  }) async {
    final v = _view!;
    final pay = amount ?? line.proposed;
    if (pay > line.proposed + v.plan.buffer) {
      throw const AllocationException('That’s more than is unallocated.');
    }
    final dest = destination ?? line.need.destination;
    // Topping up: the old reservation (and any planned transfer) is
    // replaced by one for the new total.
    final existing = v.decisionFor(line.need.key);
    if (existing != null) {
      if (existing.status == DecisionStatus.transferred) {
        throw const AllocationException('Already moved this period.');
      }
      await _repo.release(existing.id);
    }
    final move = moveFor(line, pay + line.reserved, dest);
    await _repo.reserve(
      v.scope,
      line.need,
      amount: pay + line.reserved,
      destination: dest,
      moveFrom: move.from,
      transferPaise: move.transfer,
    );
    await _accounts.refresh();
    await refresh();
  }

  /// Approve every line with something proposed. Returns how many.
  Future<int> approveAll() async {
    var n = 0;
    final keys = [
      for (final l in [...?_view?.plan.lines]) l.need.key,
    ];
    for (final key in keys) {
      // Each approval changes the plan, so use the line as it is now.
      final line = _view?.plan.lines
          .where((l) => l.need.key == key)
          .firstOrNull;
      if (line == null || line.proposed <= 0) continue;
      if (_view!.decisionFor(key)?.status == DecisionStatus.transferred) {
        continue;
      }
      await approve(line);
      n++;
    }
    return n;
  }

  Future<void> skip(AllocationNeed need) async {
    await _repo.skip(_view!.scope, need);
    await refresh();
  }

  Future<void> markTransferred(AllocationDecision d) async {
    await _repo.markTransferred(d.id);
    await _accounts.refresh();
    await refresh();
  }

  Future<void> release(AllocationDecision d) async {
    await _repo.release(d.id);
    await _accounts.refresh();
    await refresh();
  }

  Future<void> saveSettings(AllocationSettings s) async {
    await _repo.saveSettings(s);
    await refresh();
  }

  /// Accounts with a role, for picking a destination.
  List<String> destinations() => [
    for (final a in _accounts.active)
      if (a.account.status == AccountStatus.active) a.account.name,
  ];

  @override
  void dispose() {
    if (_attached) {
      for (final c in [
        _accounts,
        _budgets,
        _cards,
        _loans,
        _recurring,
        _cycles,
      ]) {
        c.removeListener(refresh);
      }
      _goals?.removeListener(refresh);
      _emergency?.removeListener(refresh);
    }
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';

import '../../core/finance/salary_cycle.dart';
import '../../data/repositories/cycle_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../expenses/expenses_controller.dart';

/// Everything one cycle's card shows. All paise.
class CycleSummary {
  final CycleRange cycle;
  final CycleIncome income;
  final int spent;
  final Map<String, int> categories;

  /// Only for the open cycle.
  final CycleStanding? standing;

  const CycleSummary({
    required this.cycle,
    required this.income,
    required this.spent,
    required this.categories,
    this.standing,
  });

  /// Income received this cycle minus what was spent. Upcoming bills, EMIs
  /// and card dues are not taken off yet (they arrive in later phases), so
  /// this is never labelled "safe to spend".
  int get leftFromIncome => income.total - spent;
}

class CycleController extends ChangeNotifier {
  final CycleRepository _repo;
  final TransactionRepository _txns;
  CycleController({CycleRepository? repo, TransactionRepository? txnRepo})
    : _repo = repo ?? CycleRepository(),
      _txns = txnRepo ?? TransactionRepository();

  ExpensesController? _expenses;

  SalaryProfile _profile = const SalaryProfile();
  SalaryProfile get profile => _profile;

  List<CycleRange> _cycles = [];

  /// Oldest first.
  List<CycleRange> get cycles => _cycles;
  bool get hasCycles => _cycles.isNotEmpty;

  CycleSummary? _current;

  /// The open (newest) cycle, if any has been started.
  CycleSummary? get current => _current;

  Future<void> init() => refresh();

  /// Recomputes whenever the ledger changes, so cycle totals never lag.
  void attach(ExpensesController expenses) {
    _expenses?.removeListener(refresh);
    _expenses = expenses..addListener(refresh);
  }

  Future<void> refresh() async {
    _profile = await _repo.profile();
    _cycles = resolveCycles(await _repo.list());
    _current = _cycles.isEmpty ? null : await summaryFor(_cycles.last);
    notifyListeners();
  }

  Future<CycleSummary> summaryFor(CycleRange c, {DateTime? today}) async {
    final now = today ?? DateTime.now();
    final end = c.queryEnd(now);
    final (income, totals, categories) = await (
      _repo.incomeFor(c, now),
      _txns.totalsRange(c.start, end),
      _txns.categoryTotalsRange(c.start, end),
    ).wait;
    return CycleSummary(
      cycle: c,
      income: income,
      spent: totals.expense,
      categories: categories,
      standing: c.isOpen ? standingOf(c, _profile, now) : null,
    );
  }

  /// The cycle before [c], or null.
  CycleRange? previousOf(CycleRange c) {
    final i = _cycles.indexWhere((x) => x.record.id == c.record.id);
    return i > 0 ? _cycles[i - 1] : null;
  }

  CycleRange? nextOf(CycleRange c) {
    final i = _cycles.indexWhere((x) => x.record.id == c.record.id);
    return i >= 0 && i + 1 < _cycles.length ? _cycles[i + 1] : null;
  }

  Future<void> saveProfile(SalaryProfile p) async {
    await _repo.saveProfile(p);
    await refresh();
  }

  /// Throws [CycleException] with a user-facing message when refused.
  Future<void> recordSalary({
    required int amountPaise,
    required DateTime date,
    String? account,
    bool alreadyInBalance = false,
    String? note,
  }) async {
    await _repo.recordSalary(
      amountPaise: amountPaise,
      date: date,
      account: account,
      alreadyInBalance: alreadyInBalance,
      note: note,
    );
    // A new income row changes month totals and balances too; the
    // expenses refresh also refreshes this controller via [attach].
    if (_expenses != null) {
      await _expenses!.refresh();
    } else {
      await refresh();
    }
  }

  Future<void> startCycle(DateTime date) async {
    await _repo.startCycle(date);
    await refresh();
  }

  Future<void> moveStart(int id, DateTime date) async {
    await _repo.moveStart(id, date);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _repo.remove(id);
    await refresh();
  }

  @override
  void dispose() {
    _expenses?.removeListener(refresh);
    super.dispose();
  }
}

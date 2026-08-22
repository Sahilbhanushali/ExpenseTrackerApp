import 'package:flutter/foundation.dart';

import '../../data/models/goal.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/account_repository.dart';
import '../../data/repositories/goal_repository.dart';
import '../../data/repositories/transaction_repository.dart';

class GoalProgress {
  final Goal goal;
  final double saved;
  const GoalProgress({required this.goal, required this.saved});

  double get remaining => (goal.target - saved).clamp(0, double.infinity);
  double get pct =>
      goal.target > 0 ? (saved / goal.target).clamp(0.0, 1.0) : 0.0;
  bool get isComplete => saved >= goal.target;
}

/// Multiple savings goals — port of the reference ledger's goal tiles.
class GoalsController extends ChangeNotifier {
  final GoalRepository _goalRepo;
  final TransactionRepository _txnRepo;
  final AccountRepository _accountRepo;

  GoalsController({
    GoalRepository? goalRepo,
    TransactionRepository? txnRepo,
    AccountRepository? accountRepo,
  }) : _goalRepo = goalRepo ?? GoalRepository(),
       _txnRepo = txnRepo ?? TransactionRepository(),
       _accountRepo = accountRepo ?? AccountRepository();

  List<GoalProgress> _goals = [];
  List<GoalProgress> get goals => _goals;

  Future<void> init() => refresh();

  Future<void> refresh() async {
    final goals = await _goalRepo.list();
    final withProgress = <GoalProgress>[];
    for (final g in goals) {
      final saved = await _goalRepo.savedAmount(g.id!);
      withProgress.add(GoalProgress(goal: g, saved: saved));
    }
    _goals = withProgress;
    notifyListeners();
  }

  Future<void> add(String name, double target, {String? note}) async {
    await _goalRepo.add(name, target, note: note);
    await refresh();
  }

  /// Logs a contribution as an expense linked to this goal — reduces
  /// available balance the same way any other spend does, matching the
  /// reference app's "money set aside" semantics.
  Future<void> contribute(int goalId, double amount) async {
    final account = await _accountRepo.defaultAccount();
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final goal = _goals.firstWhere((g) => g.goal.id == goalId).goal;
    await _txnRepo.add(
      Transaction(
        date: date,
        category: 'other',
        amount: amount,
        note: 'Goal: ${goal.name}',
        type: TxnType.expense,
        createdAt: now.toIso8601String(),
        account: account,
        goalId: goalId,
      ),
    );
    await refresh();
  }

  Future<void> update(
    int id, {
    String? name,
    double? target,
    String? note,
  }) async {
    await _goalRepo.update(id, name: name, target: target, note: note);
    await refresh();
  }

  Future<void> remove(int id) async {
    await _goalRepo.remove(id);
    await refresh();
  }
}

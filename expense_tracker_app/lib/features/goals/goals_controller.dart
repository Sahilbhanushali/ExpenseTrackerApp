import 'package:flutter/foundation.dart';

import '../../core/finance/wealth.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../accounts/accounts_controller.dart';

/// A goal with what's been saved toward it.
class GoalStanding {
  final Goal goal;

  /// In paise.
  final int saved;
  const GoalStanding({required this.goal, required this.saved});

  GoalProgress get progress => GoalProgress(
    target: goal.targetPaise,
    saved: saved,
    targetDate: goal.targetDate,
    monthlyContribution: goal.monthlyContributionPaise,
  );
}

class GoalsController extends ChangeNotifier {
  final GoalRepository _repo;
  GoalsController({GoalRepository? goalRepo})
    : _repo = goalRepo ?? GoalRepository();

  AccountsController? _accounts;
  void attach(AccountsController accounts) => _accounts = accounts;

  List<GoalStanding> _goals = [];

  /// Priority order, highest first.
  List<GoalStanding> get goals => _goals;
  List<GoalStanding> get active =>
      _goals.where((g) => !g.goal.achieved).toList();

  Future<void> init() => refresh();

  Future<void> refresh() async {
    final goals = await _repo.list();
    final saved = await _repo.saved();
    _goals = [
      for (final g in goals) GoalStanding(goal: g, saved: saved[g.id] ?? 0),
    ];
    notifyListeners();
  }

  /// Earmarked per account — to warn when goals claim more than the
  /// account holds.
  Map<String, int> earmarked() {
    final out = <String, int>{};
    for (final g in active) {
      final a = g.goal.account;
      if (a != null) out[a] = (out[a] ?? 0) + g.saved;
    }
    return out;
  }

  /// All throw [GoalException] with a message for the user.
  Future<void> save(Goal g) async {
    await _repo.save(g);
    await refresh();
  }

  Future<void> contribute(
    GoalStanding g, {
    required String from,
    required int amountPaise,
    bool done = true,
  }) async {
    await _repo.contribute(
      g.goal.id!,
      from: from,
      amountPaise: amountPaise,
      done: done,
    );
    await refresh();
    await _accounts?.refresh();
  }

  Future<void> withdraw(
    GoalStanding g, {
    required String to,
    required int amountPaise,
  }) async {
    await _repo.withdraw(g.goal.id!, to: to, amountPaise: amountPaise);
    await refresh();
    await _accounts?.refresh();
  }

  Future<void> setAchieved(GoalStanding g, bool achieved) async {
    await _repo.setAchieved(g.goal.id!, achieved);
    await refresh();
  }

  Future<void> remove(GoalStanding g) async {
    await _repo.remove(g.goal.id!);
    await refresh();
  }
}

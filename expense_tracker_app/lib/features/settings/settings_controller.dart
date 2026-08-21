import 'package:flutter/foundation.dart';

import '../../data/models/app_config.dart';
import '../../data/repositories/config_repository.dart';

/// Owns AppConfig (config.json equivalent) — currency, budgets, savings
/// goal, custom categories. Mirrors bot.py's load_config/save_config calls.
class SettingsController extends ChangeNotifier {
  final ConfigRepository _repo;
  SettingsController([ConfigRepository? repo]) : _repo = repo ?? ConfigRepository();

  AppConfig _config = const AppConfig();
  AppConfig get config => _config;
  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> init() async {
    _config = await _repo.load();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist(AppConfig next) async {
    _config = next;
    await _repo.save(next);
    notifyListeners();
  }

  Future<void> setMonthlyBudget(double amount) => _persist(_config.copyWith(monthlyBudget: amount));

  Future<void> setCategoryBudget(String category, double amount) {
    final budgets = Map<String, double>.from(_config.budgets)..[category] = amount;
    return _persist(_config.copyWith(budgets: budgets));
  }

  Future<void> setBudgets(Map<String, double> budgets) => _persist(_config.copyWith(budgets: budgets));

  Future<void> setSavingsGoal(double amount, String label) =>
      _persist(_config.copyWith(savingsGoal: SavingsGoal(amount: amount, label: label)));

  Future<void> setCurrency(String currency) => _persist(_config.copyWith(currency: currency));

  Future<void> addCategory(String name, List<String> keywords) {
    final custom = Map<String, List<String>>.from(_config.customCategories);
    final existing = custom[name] ?? [];
    custom[name] = {...existing, ...keywords}.toList()..sort();
    return _persist(_config.copyWith(customCategories: custom));
  }

  /// Effective budget: capped at logged income once any is logged this
  /// month, same as bot.py's effective_budget().
  double effectiveBudget(double income) {
    return income > 0 ? (_config.monthlyBudget < income ? _config.monthlyBudget : income) : _config.monthlyBudget;
  }
}

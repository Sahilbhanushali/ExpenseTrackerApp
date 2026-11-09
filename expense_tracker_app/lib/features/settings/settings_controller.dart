import 'package:flutter/foundation.dart';

import '../../data/models/app_config.dart';
import '../../data/repositories/config_repository.dart';

/// Owns AppConfig (config.json equivalent) — currency, budgets, savings
/// goal, custom categories. Mirrors bot.py's load_config/save_config calls.
class SettingsController extends ChangeNotifier {
  final ConfigRepository _repo;
  SettingsController([ConfigRepository? repo])
    : _repo = repo ?? ConfigRepository();

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

  Future<void> setSavingsGoal(int paise, String label) => _persist(
    _config.copyWith(
      savingsGoal: SavingsGoal(amountPaise: paise, label: label),
    ),
  );

  Future<void> setThemeMode(String mode) =>
      _persist(_config.copyWith(themeMode: mode));

  Future<void> setReminders({bool? on, int? daysBefore}) => _persist(
    _config.copyWith(remindersOn: on, reminderDaysBefore: daysBefore),
  );

  Future<void> markBudgetsImported() =>
      _persist(_config.copyWith(budgetsImported: true));

  Future<void> setPeriodView(String view) =>
      _persist(_config.copyWith(periodView: view));

  Future<void> setCurrency(String currency) =>
      _persist(_config.copyWith(currency: currency));

  Future<void> addCategory(String name, List<String> keywords) {
    final custom = Map<String, List<String>>.from(_config.customCategories);
    final existing = custom[name] ?? [];
    custom[name] = {...existing, ...keywords}.toList()..sort();
    return _persist(_config.copyWith(customCategories: custom));
  }

  Future<void> updateCategoryKeywords(String name, List<String> keywords) {
    final custom = Map<String, List<String>>.from(_config.customCategories);
    custom[name] = keywords..sort();
    return _persist(_config.copyWith(customCategories: custom));
  }

  Future<void> removeCategory(String name) {
    final custom = Map<String, List<String>>.from(_config.customCategories)
      ..remove(name);
    return _persist(_config.copyWith(customCategories: custom));
  }
}

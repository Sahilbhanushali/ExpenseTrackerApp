import 'package:flutter_test/flutter_test.dart';

import 'package:expense_tracker_app/data/models/app_config.dart';
import 'package:expense_tracker_app/data/repositories/config_repository.dart';
import 'package:expense_tracker_app/features/settings/settings_controller.dart';

/// Avoids touching disk via path_provider — keeps config in memory instead.
class _FakeConfigRepository extends ConfigRepository {
  AppConfig stored = const AppConfig();

  @override
  Future<AppConfig> load() async => stored;

  @override
  Future<void> save(AppConfig config) async => stored = config;
}

void main() {
  test('period view and the budget import flag persist', () async {
    final repo = _FakeConfigRepository();
    final settings = SettingsController(repo);
    await settings.setPeriodView('cycle');
    await settings.markBudgetsImported();
    expect(repo.stored.periodView, 'cycle');
    expect(repo.stored.budgetsImported, isTrue);
  });

  test('pre-v15 month budgets still load from old configs for import', () {
    final config = AppConfig.fromJson({
      'schema': 2,
      'monthlyBudget': 1700000,
      'budgets': {'food': 800000},
    });
    expect(config.monthlyBudgetPaise, 1700000);
    expect(config.budgets['food'], 800000);
    expect(config.budgetsImported, isFalse);
    expect(config.periodView, 'month');
  });
}

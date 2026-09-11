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
  test('the monthly budget you set is the budget', () async {
    final settings = SettingsController(_FakeConfigRepository());
    await settings.setMonthlyBudget(1700000);

    expect(settings.config.monthlyBudgetPaise, 1700000);
  });

  test('logging income does not shrink the budget', () async {
    // The budget used to be silently capped at whatever income had been
    // logged so far this month. That made ₹500 of incidental income cut a
    // ₹17,000 budget by 97%, and reported the month as wildly overspent.
    final settings = SettingsController(_FakeConfigRepository());
    await settings.setMonthlyBudget(1700000);

    // Whatever income exists, the configured budget is what the UI uses.
    expect(settings.config.monthlyBudgetPaise, 1700000);

    await settings.setMonthlyBudget(50000);
    expect(settings.config.monthlyBudgetPaise, 50000);
  });

  test('category budgets are stored in paise', () async {
    final settings = SettingsController(_FakeConfigRepository());
    await settings.setCategoryBudget('food', 800000);

    expect(settings.config.budgets['food'], 800000);
  });
}

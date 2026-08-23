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
  test(
    'effectiveBudget falls back to the flat budget when no income logged yet',
    () async {
      final settings = SettingsController(_FakeConfigRepository());
      await settings.setMonthlyBudget(20000);

      expect(settings.effectiveBudget(0), 20000);
    },
  );

  test(
    'effectiveBudget is capped at income once income exceeds the budget',
    () async {
      final settings = SettingsController(_FakeConfigRepository());
      await settings.setMonthlyBudget(20000);

      expect(settings.effectiveBudget(15000), 15000);
    },
  );

  test(
    'effectiveBudget uses the flat budget when income is below it',
    () async {
      final settings = SettingsController(_FakeConfigRepository());
      await settings.setMonthlyBudget(20000);

      expect(settings.effectiveBudget(50000), 20000);
    },
  );
}

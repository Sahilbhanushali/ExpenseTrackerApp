import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;

import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/page_transitions.dart';
import '../../data/datasources/app_database.dart';
import '../../data/models/app_config.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/repositories/export_repository.dart';
import '../accounts/accounts_controller.dart';
import '../expenses/expenses_controller.dart';
import '../goals/goals_controller.dart';
import '../goals/goals_screen.dart';
import '../lending/lending_controller.dart';
import '../recurring/recurring_controller.dart';
import '../wishlist/wishlist_controller.dart';
import 'budget_planner_screen.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editAmount(BuildContext context, String title, double current, ValueChanged<double> onSave) async {
    final controller = TextEditingController(text: current == 0 ? '' : current.toStringAsFixed(0));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, keyboardType: TextInputType.number, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result == true) {
      final value = double.tryParse(controller.text.replaceAll(',', ''));
      if (value != null && value >= 0) onSave(value);
    }
  }

  Future<void> _addCategory(BuildContext context, SettingsController settings) async {
    final nameController = TextEditingController();
    final keywordsController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name (e.g. pets)')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: keywordsController, decoration: const InputDecoration(labelText: 'Keywords, comma-separated')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result == true) {
      final name = nameController.text.trim().toLowerCase();
      final keywords = keywordsController.text.split(',').map((k) => k.trim().toLowerCase()).where((k) => k.isNotEmpty).toList();
      if (name.isEmpty || keywords.isEmpty) return;
      await settings.addCategory(name, keywords);
    }
  }

  Future<void> _exportCsv(BuildContext context) async {
    final file = await ExportRepository().exportCsv();
    await Share.shareXFiles([XFile(file.path)], text: 'Expense export');
  }

  Future<void> _exportBackup(BuildContext context) async {
    final repo = ExportRepository();
    final db = await repo.dbFilePath();
    final config = await repo.configFilePath();
    final files = <XFile>[];
    if (await db.exists()) files.add(XFile(db.path));
    if (await config.exists()) files.add(XFile(config.path));
    if (files.isEmpty) return;
    await Share.shareXFiles(files, text: 'Expense tracker backup');
  }

  Future<void> _importCsv(BuildContext context) async {
    const typeGroup = file_selector.XTypeGroup(label: 'CSV', extensions: ['csv']);
    final picked = await file_selector.openFile(acceptedTypeGroups: [typeGroup]);
    final path = picked?.path;
    if (path == null || !context.mounted) return;

    final imported = await ExportRepository().importCsv(File(path));
    if (!context.mounted) return;
    await context.read<ExpensesController>().refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $imported transaction(s).')),
    );
  }

  Future<void> _resetAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all data?'),
        content: const Text(
          'This permanently deletes every transaction, account, recurring bill, '
          'wishlist item, goal, and budget setting on this device. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Reset everything')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final settingsController = context.read<SettingsController>();
    final expenses = context.read<ExpensesController>();
    final accounts = context.read<AccountsController>();
    final lending = context.read<LendingController>();
    final recurring = context.read<RecurringController>();
    final wishlist = context.read<WishlistController>();
    final goals = context.read<GoalsController>();
    final messenger = ScaffoldMessenger.of(context);

    await AppDatabase.instance.resetAll();
    await ConfigRepository().save(const AppConfig());
    await settingsController.init();
    await Future.wait([
      expenses.refresh(),
      accounts.refresh(),
      lending.refresh(),
      recurring.refresh(),
      wishlist.refresh(),
      goals.refresh(),
    ]);
    messenger.showSnackBar(const SnackBar(content: Text('All data reset.')));
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final config = settings.config;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text('Budget', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Monthly budget'),
              trailing: Text(formatMoney(config.monthlyBudget, config.currency)),
              onTap: () => _editAmount(context, 'Monthly budget', config.monthlyBudget, settings.setMonthlyBudget),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Savings goals'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(FadeSlideRoute(page: const GoalsScreen())),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Category budgets', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Split your monthly budget across categories — adjusting one '
                  'automatically rebalances the rest so the total always matches.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Allocated: ${formatMoney(config.budgets.values.fold(0.0, (s, v) => s + v), config.currency)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.of(context).push(FadeSlideRoute(page: const BudgetPlannerScreen())),
                      child: const Text('Open planner'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Categories', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (config.customCategories.isEmpty)
                  const Text('No custom categories yet.')
                else
                  ...config.customCategories.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('${e.key}: ${e.value.join(', ')}'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: () => _addCategory(context, settings),
                  icon: const Icon(Icons.add),
                  label: const Text('Add category'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Data', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Export transactions (CSV)'),
                  onTap: () => _exportCsv(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup (database + config)'),
                  onTap: () => _exportBackup(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.file_upload_outlined),
                  title: const Text('Import transactions (CSV)'),
                  onTap: () => _importCsv(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_outlined),
                  title: const Text('Reset all data'),
                  textColor: Colors.red,
                  iconColor: Colors.red,
                  onTap: () => _resetAll(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:io';

import 'package:file_selector/file_selector.dart' as file_selector;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_lock_service.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../data/datasources/app_database.dart';
import '../../data/models/app_config.dart';
import '../../data/repositories/config_repository.dart';
import '../../data/repositories/export_repository.dart';
import '../accounts/accounts_controller.dart';
import '../expenses/expenses_controller.dart';
import '../goals/goals_controller.dart';
import '../goals/goals_screen.dart';
import '../lending/lending_controller.dart';
import '../loans/loans_controller.dart';
import '../recurring/recurring_controller.dart';
import '../security/lock_screen.dart';
import '../wishlist/wishlist_controller.dart';
import 'budget_planner_screen.dart';
import 'settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editAmount(
    BuildContext context,
    String title,
    int currentPaise,
    ValueChanged<int> onSave,
  ) async {
    final controller = TextEditingController(
      text: currentPaise == 0 ? '' : paiseToEditString(currentPaise),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      final value = parseRupeesToPaise(controller.text);
      if (value != null && value >= 0) onSave(value);
    }
  }

  Future<void> _addCategory(
    BuildContext context,
    SettingsController settings,
  ) async {
    final nameController = TextEditingController();
    final keywordsController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name (e.g. pets)'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: keywordsController,
              decoration: const InputDecoration(
                labelText: 'Keywords, comma-separated',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) {
      final name = nameController.text.trim().toLowerCase();
      final keywords = keywordsController.text
          .split(',')
          .map((k) => k.trim().toLowerCase())
          .where((k) => k.isNotEmpty)
          .toList();
      if (name.isEmpty || keywords.isEmpty) return;
      await settings.addCategory(name, keywords);
    }
  }

  Future<void> _editCategory(
    BuildContext context,
    SettingsController settings,
    String name,
    List<String> keywords,
  ) async {
    final keywordsController = TextEditingController(text: keywords.join(', '));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(name),
        content: TextField(
          controller: keywordsController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Keywords, comma-separated',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete category'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == 'delete') {
      await settings.removeCategory(name);
    } else if (result == 'save') {
      final newKeywords = keywordsController.text
          .split(',')
          .map((k) => k.trim().toLowerCase())
          .where((k) => k.isNotEmpty)
          .toList();
      if (newKeywords.isEmpty) return;
      await settings.updateCategoryKeywords(name, newKeywords);
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
    const typeGroup = file_selector.XTypeGroup(
      label: 'CSV',
      extensions: ['csv'],
    );
    final picked = await file_selector.openFile(
      acceptedTypeGroups: [typeGroup],
    );
    final path = picked?.path;
    if (path == null || !context.mounted) return;

    final imported = await ExportRepository().importCsv(File(path));
    if (!context.mounted) return;
    await context.read<ExpensesController>().refresh();
    if (!context.mounted) return;
    await context.read<AccountsController>().refresh();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Imported $imported transaction(s).')),
    );
  }

  /// Swaps the live database for a previously exported backup. Destructive
  /// in the same way Reset is, so it asks the same way.
  Future<void> _restoreBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'Everything currently in Spendo is replaced by the backup you '
          'pick. Export a backup first if you want to keep what is here now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Pick a backup'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    const typeGroup = file_selector.XTypeGroup(label: 'Spendo backup');
    final picked = await file_selector.openFile(
      acceptedTypeGroups: [typeGroup],
    );
    final path = picked?.path;
    if (path == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final settingsController = context.read<SettingsController>();
    final reload = _reloadAll(context);

    try {
      await ExportRepository().restoreFromFile(File(path));
    } on RestoreException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    await settingsController.init();
    await reload();
    messenger.showSnackBar(const SnackBar(content: Text('Backup restored.')));
  }

  /// Re-reads every controller from the database — used after any operation
  /// that replaces the data underneath them.
  Future<void> Function() _reloadAll(BuildContext context) {
    final expenses = context.read<ExpensesController>();
    final accounts = context.read<AccountsController>();
    final lending = context.read<LendingController>();
    final recurring = context.read<RecurringController>();
    final wishlist = context.read<WishlistController>();
    final goals = context.read<GoalsController>();
    final loans = context.read<LoansController>();
    return () => Future.wait([
      expenses.refresh(),
      accounts.refresh(),
      lending.refresh(),
      recurring.refresh(),
      wishlist.refresh(),
      goals.refresh(),
      loans.refresh(),
    ]);
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset everything'),
          ),
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

  Future<void> _pickCurrency(
    BuildContext context,
    SettingsController settings,
  ) async {
    const options = ['₹', r'$', '€', '£', '¥', 'AED ', 'SGD '];
    final current = settings.config.currency;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                0,
                AppSpacing.page,
                AppSpacing.sm,
              ),
              child: Text(
                'Currency symbol',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final c in options)
              ListTile(
                title: Text(c.trim()),
                trailing: c == current
                    ? Icon(Icons.check_rounded, color: context.palette.savings)
                    : null,
                onTap: () => Navigator.pop(context, c),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (picked != null && picked != current) await settings.setCurrency(picked);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final config = settings.config;
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final allocated = config.budgets.values.fold<int>(0, (s, v) => s + v);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsivePage(
        builder: (context, gutter) => ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            AppSpacing.sm,
            gutter,
            AppSpacing.xl,
          ),
          children: [
            _SettingsGroup(
              title: 'Appearance',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const ListRow(
                        icon: Icons.palette_outlined,
                        title: 'Theme',
                        subtitle: 'Follow the system or pick one',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: 'system',
                            icon: Icon(Icons.brightness_auto_outlined),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: 'light',
                            icon: Icon(Icons.light_mode_outlined),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: 'dark',
                            icon: Icon(Icons.dark_mode_outlined),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {config.themeMode},
                        onSelectionChanged: (s) =>
                            settings.setThemeMode(s.first),
                      ),
                    ],
                  ),
                ),
                ListRow(
                  icon: Icons.currency_exchange_rounded,
                  title: 'Currency',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(config.currency.trim(), style: text.titleMedium),
                      const RowChevron(),
                    ],
                  ),
                  onTap: () => _pickCurrency(context, settings),
                ),
              ],
            ),
            _SettingsGroup(
              title: 'Budget',
              children: [
                ListRow(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Monthly budget',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMoney(config.monthlyBudgetPaise, config.currency),
                        style: text.moneyStyle(14),
                      ),
                      const RowChevron(),
                    ],
                  ),
                  onTap: () => _editAmount(
                    context,
                    'Monthly budget',
                    config.monthlyBudgetPaise,
                    settings.setMonthlyBudget,
                  ),
                ),
                ListRow(
                  icon: Icons.pie_chart_outline_rounded,
                  title: 'Category budgets',
                  subtitle:
                      'Allocated ${formatMoney(allocated, config.currency)} — split across categories',
                  trailing: const RowChevron(),
                  onTap: () => Navigator.of(context)
                      .push(FadeSlideRoute(page: const BudgetPlannerScreen())),
                ),
                ListRow(
                  icon: Icons.flag_outlined,
                  title: 'Savings goals',
                  trailing: const RowChevron(),
                  onTap: () =>
                      Navigator.of(context)
                          .push(FadeSlideRoute(page: const GoalsScreen())),
                ),
              ],
            ),
            _SettingsGroup(
              title: 'Custom categories',
              children: [
                if (config.customCategories.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Text(
                      'Add your own categories with keywords — quick-add will '
                      'file matching entries under them automatically.',
                      style: text.bodySmall,
                    ),
                  )
                else
                  for (final e in config.customCategories.entries)
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () =>
                          _editCategory(context, settings, e.key, e.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            CategoryIcon(category: e.key),
                            const SizedBox(width: AppSpacing.md - 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    e.key,
                                    style: text.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    e.value.join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const RowChevron(),
                          ],
                        ),
                      ),
                    ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addCategory(context, settings),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add category'),
                  ),
                ),
              ],
            ),
            const _SettingsGroup(
              title: 'Security',
              children: [_SecuritySection()],
            ),
            _SettingsGroup(
              title: 'Data',
              children: [
                ListRow(
                  icon: Icons.file_download_outlined,
                  title: 'Export transactions (CSV)',
                  trailing: const RowChevron(),
                  onTap: () => _exportCsv(context),
                ),
                ListRow(
                  icon: Icons.backup_outlined,
                  title: 'Backup (database + config)',
                  trailing: const RowChevron(),
                  onTap: () => _exportBackup(context),
                ),
                ListRow(
                  icon: Icons.file_upload_outlined,
                  title: 'Import transactions (CSV)',
                  trailing: const RowChevron(),
                  onTap: () => _importCsv(context),
                ),
                ListRow(
                  icon: Icons.settings_backup_restore_rounded,
                  title: 'Restore from backup',
                  subtitle: 'Replaces everything on this device',
                  trailing: const RowChevron(),
                  onTap: () => _restoreBackup(context),
                ),
              ],
            ),
            _SettingsGroup(
              title: 'Danger zone',
              children: [
                ListRow(
                  icon: Icons.delete_forever_outlined,
                  iconColor: p.expense,
                  title: 'Reset all data',
                  subtitle: 'Permanently deletes every entry',
                  titleStyle: text.bodyLarge?.copyWith(
                    color: p.expense,
                    fontWeight: FontWeight.w600,
                  ),
                  onTap: () => _resetAll(context),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                children: [
                  Text('Spendo', style: text.titleSmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Your data stays on this device.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled card of settings rows separated by hairlines.
class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md - 4,
              vertical: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const Divider(),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// PIN + biometric app lock toggle. State lives in secure storage, not
/// AppConfig — it's device-local security, not synced/exported config — so
/// it manages its own async load independent of SettingsController.
class _SecuritySection extends StatefulWidget {
  const _SecuritySection();

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AppLockService.instance.isEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _onToggle(bool value) async {
    if (value) {
      final created = await Navigator.of(context)
          .push<bool>(MaterialPageRoute(builder: (_) => const SetPinScreen()));
      if (created == true && mounted) setState(() => _enabled = true);
    } else {
      await AppLockService.instance.disable();
      if (mounted) setState(() => _enabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListRow(
      icon: Icons.lock_outline_rounded,
      title: 'App lock',
      subtitle: 'Require a PIN or biometric to open the app',
      trailing: Switch(
        value: _enabled ?? false,
        onChanged: _enabled == null ? null : _onToggle,
      ),
    );
  }
}

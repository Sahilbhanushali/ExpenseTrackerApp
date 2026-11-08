import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/animated_money_text.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/staggered_list.dart';
import '../../data/models/account.dart';
import '../expenses/transactions_screen.dart';
import '../settings/settings_controller.dart';
import 'accounts_controller.dart';

String _typeLabel(AccountType t) => switch (t) {
  AccountType.cash => 'Cash & bank',
  AccountType.investment => 'Investments',
  AccountType.emergencyFund => 'Emergency fund',
};

IconData _typeIcon(AccountType t) => switch (t) {
  AccountType.cash => Icons.account_balance_wallet_outlined,
  AccountType.investment => Icons.trending_up_outlined,
  AccountType.emergencyFund => Icons.shield_outlined,
};

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _showAddAccount(BuildContext context) async {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    final currentValueController = TextEditingController();
    AccountType type = AccountType.cash;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name (e.g. cash, bank)',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: type == AccountType.cash
                      ? 'Opening balance'
                      : 'Amount invested / set aside',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<AccountType>(
                segments: const [
                  ButtonSegment(value: AccountType.cash, label: Text('Cash')),
                  ButtonSegment(
                    value: AccountType.investment,
                    label: Text('Investment'),
                  ),
                  ButtonSegment(
                    value: AccountType.emergencyFund,
                    label: Text('Emergency'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              if (type == AccountType.investment) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: currentValueController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Current value (optional)',
                    helperText: 'Leave blank if it matches what you put in',
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      final name = nameController.text.trim();
      final balance = parseRupeesToPaise(balanceController.text) ?? 0;
      if (name.isEmpty) return;
      final controller = context.read<AccountsController>();
      if (controller.nameTaken(name)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Account '$name' already exists.")),
          );
        }
        return;
      }
      final currentValue = type == AccountType.investment
          ? parseRupeesToPaise(currentValueController.text)
          : null;
      await controller.add(
        name,
        balance,
        type: type,
        currentValuePaise: currentValue,
      );
    }
  }

  Future<void> _showEditAccount(BuildContext context, AccountBalance a) async {
    final nameController = TextEditingController(text: a.account.name);
    final balanceController = TextEditingController(
      text: paiseToEditString(a.account.openingBalancePaise),
    );
    final currentValueController = TextEditingController(
      text: a.account.currentValuePaise == null
          ? ''
          : paiseToEditString(a.account.currentValuePaise!),
    );
    AccountType type = a.account.type;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: balanceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: type == AccountType.cash
                      ? 'Opening balance'
                      : 'Amount invested / set aside',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<AccountType>(
                segments: const [
                  ButtonSegment(value: AccountType.cash, label: Text('Cash')),
                  ButtonSegment(
                    value: AccountType.investment,
                    label: Text('Investment'),
                  ),
                  ButtonSegment(
                    value: AccountType.emergencyFund,
                    label: Text('Emergency'),
                  ),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              if (type == AccountType.investment) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: currentValueController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Current value (optional)',
                    helperText: 'Leave blank if it matches what you put in',
                  ),
                ),
              ],
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
      ),
    );
    if (result != true || !context.mounted) return;
    final name = nameController.text.trim();
    final balance = parseRupeesToPaise(balanceController.text);
    if (name.isEmpty || balance == null) return;
    final controller = context.read<AccountsController>();
    if (name != a.account.name &&
        controller.nameTaken(name, excludeId: a.account.id)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Account '$name' already exists.")),
        );
      }
      return;
    }
    final currentValue = type == AccountType.investment
        ? parseRupeesToPaise(currentValueController.text)
        : null;
    await controller.update(
      a.account.id!,
      name: name,
      openingBalancePaise: balance,
      type: type,
      currentValue: currentValue,
    );
  }

  Future<void> _confirmDelete(BuildContext context, AccountBalance a) async {
    final controller = context.read<AccountsController>();
    final linked = await controller.linkedRecordCount(a.account.name);
    if (!context.mounted) return;

    // Nothing references it — a plain confirm is enough.
    if (linked == 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete this account?'),
          content: Text('"${a.account.name}" has no transactions.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) await controller.remove(a.account.id!);
      return;
    }

    // Otherwise the history has to go somewhere, or those amounts would
    // disappear from balances while still counting in reports.
    final others = controller.accounts
        .where((o) => o.account.id != a.account.id)
        .map((o) => o.account.name)
        .toList();

    if (others.isEmpty) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Can\'t delete this account'),
          content: Text(
            '"${a.account.name}" has $linked linked '
            '${linked == 1 ? 'record' : 'records'} and it\'s your only '
            'account. Create another account first so they have somewhere '
            'to go.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    var moveTo = others.first;
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Delete this account?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '"${a.account.name}" has $linked linked '
                '${linked == 1 ? 'record' : 'records'}. Move them to:',
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: moveTo,
                decoration: const InputDecoration(labelText: 'Move history to'),
                items: others
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setState(() => moveTo = v ?? moveTo),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Move & delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await controller.remove(a.account.id!, reassignTo: moveTo);
    }
  }

  Future<void> _showTransfer(BuildContext context, List<String> names) async {
    if (names.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least two accounts first.')),
      );
      return;
    }
    String from = names[0];
    String to = names[1];
    final amountController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Transfer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: from,
                decoration: const InputDecoration(labelText: 'From'),
                items: names
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setState(() => from = v!),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: to,
                decoration: const InputDecoration(labelText: 'To'),
                items: names
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setState(() => to = v!),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount'),
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
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      final amount = parseRupeesToPaise(amountController.text);
      if (amount == null || amount <= 0 || from == to) return;
      await context.read<AccountsController>().transfer(from, to, amount, null);
    }
  }

  /// "Money lands in IDFC, keep 10k there, split the rest across the other
  /// accounts" — a repeatable income-splitting tool instead of doing that
  /// math by hand every payday. Never moves anything until you tap
  /// Distribute; every figure is visible and editable first.
  Future<void> _showDistribute(
    BuildContext context,
    List<AccountBalance> accounts,
    String currency,
  ) async {
    if (accounts.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least two accounts first.')),
      );
      return;
    }
    final defaultSource = accounts.firstWhere(
      (a) => a.account.isDefault,
      orElse: () => accounts.first,
    );
    String source = defaultSource.account.name;
    final amountController = TextEditingController();
    final minKeepController = TextEditingController(text: '10000');
    final targets = accounts.where((a) => a.account.name != source).toList();
    final pctControllers = <String, TextEditingController>{
      for (final t in targets)
        t.account.name: TextEditingController(text: '20'),
    };

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          void rebuildTargets(String newSource) {
            source = newSource;
            targets
              ..clear()
              ..addAll(accounts.where((a) => a.account.name != source));
            pctControllers.clear();
            for (final t in targets) {
              pctControllers[t.account.name] = TextEditingController(
                text: '20',
              );
            }
          }

          final amount = parseRupeesToPaise(amountController.text) ?? 0;
          final minKeep = parseRupeesToPaise(minKeepController.text) ?? 0;
          final available = (amount - minKeep).clamp(0, amount);
          final totalPct = pctControllers.values.fold<double>(
            0,
            (s, c) => s + (double.tryParse(c.text) ?? 0),
          );

          return AlertDialog(
            title: const Text('Distribute income'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: source,
                    decoration: const InputDecoration(
                      labelText: 'Money lands in',
                    ),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.account.name,
                            child: Text(a.account.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => rebuildTargets(v ?? source)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Amount received',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: minKeepController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Keep at least this much in $source',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Available to split: ${formatMoney(available, currency)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: available <= 0 && amount > 0
                          ? context.palette.expense
                          : null,
                    ),
                  ),
                  if (available <= 0 && amount > 0) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      amount < minKeep
                          ? '${formatMoney(minKeep - amount, currency)} short of the $source minimum — nothing to split yet.'
                          : 'This entire amount stays in $source to meet the minimum — nothing left to split.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: context.palette.expense),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  for (final t in targets) ...[
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(
                            '${t.account.name} · ${_typeLabel(t.account.type)}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: pctControllers[t.account.name],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.end,
                            decoration: const InputDecoration(suffixText: '%'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: 90,
                          child: Text(
                            formatMoney(
                              (available *
                                      (double.tryParse(
                                            pctControllers[t.account.name]!
                                                .text,
                                          ) ??
                                          0) /
                                      100)
                                  .round(),
                              currency,
                            ),
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    'Total: ${totalPct.toStringAsFixed(0)}%'
                    '${totalPct > 100 ? ' — over 100%' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: totalPct > 100 ? context.palette.expense : null,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: available <= 0 || totalPct > 100
                    ? null
                    : () async {
                        final controller = context.read<AccountsController>();
                        for (final t in targets) {
                          final pct =
                              double.tryParse(
                                pctControllers[t.account.name]!.text,
                              ) ??
                              0;
                          final share = (available * pct / 100).round();
                          if (share > 0) {
                            await controller.transfer(
                              source,
                              t.account.name,
                              share,
                              'Income distribution',
                            );
                          }
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                child: const Text('Distribute'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsController>();
    final currency = context.watch<SettingsController>().config.currency;
    final names = accounts.accounts.map((a) => a.account.name).toList();

    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final total = accounts.accounts.fold<int>(
      0,
      (s, a) => s + (a.account.currentValuePaise ?? a.balance),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'accounts_add',
        onPressed: () => _showAddAccount(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add account'),
      ),
      body: accounts.accounts.isEmpty
          ? EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              message:
                  'Add a bank account, wallet or investment to track balances.',
              action: 'Add account',
              onAction: () => _showAddAccount(context),
            )
          : ResponsivePage(
              builder: (context, gutter) => ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  AppSpacing.sm,
                  gutter,
                  AppSpacing.navClearance,
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg - 4),
                    decoration: BoxDecoration(
                      color: p.inkSurface,
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total balance',
                          style: text.labelMedium?.copyWith(
                            color: p.onInk.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AnimatedMoneyText(
                            amountPaise: total,
                            currency: currency,
                            style: text.headlineMedium?.copyWith(
                              color: p.onInk,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: _InkButton(
                                icon: Icons.swap_horiz_rounded,
                                label: 'Transfer',
                                onTap: () => _showTransfer(context, names),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: _InkButton(
                                icon: Icons.call_split_rounded,
                                label: 'Distribute',
                                onTap: () => _showDistribute(
                                  context,
                                  accounts.accounts,
                                  currency,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  for (final type in AccountType.values)
                    if (accounts.accounts.any((a) => a.account.type == type))
                      _AccountTypeSection(
                        type: type,
                        accounts: accounts.accounts
                            .where((a) => a.account.type == type)
                            .toList(),
                        currency: currency,
                        onTap: (a) => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                TransactionsScreen(account: a.account.name),
                          ),
                        ),
                        onEdit: (a) => _showEditAccount(context, a),
                        onSetDefault: (a) => context
                            .read<AccountsController>()
                            .setDefault(a.account.name),
                        onDelete: (a) => _confirmDelete(context, a),
                      ),
                ],
              ),
            ),
    );
  }
}

class _InkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _InkButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.onInk.withValues(alpha: 0.12),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.minTouch - 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: AppIconSize.md, color: p.onInk),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: p.onInk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _typeColor(AccountType t, AppPalette p) => switch (t) {
  AccountType.cash => p.savings,
  AccountType.investment => p.debt,
  AccountType.emergencyFund => p.income,
};

class _AccountTypeSection extends StatelessWidget {
  final AccountType type;
  final List<AccountBalance> accounts;
  final String currency;

  /// Opens the account's transaction history.
  final ValueChanged<AccountBalance> onTap;
  final ValueChanged<AccountBalance> onEdit;
  final ValueChanged<AccountBalance> onSetDefault;
  final ValueChanged<AccountBalance> onDelete;

  const _AccountTypeSection({
    required this.type,
    required this.accounts,
    required this.currency,
    required this.onTap,
    required this.onEdit,
    required this.onSetDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final total = accounts.fold<int>(
      0,
      (s, a) => s + (a.account.currentValuePaise ?? a.balance),
    );
    final color = _typeColor(type, p);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(_typeLabel(type), style: text.titleMedium),
                ),
                Text(formatMoney(total, currency), style: text.labelMedium),
              ],
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                for (final (i, a) in accounts.indexed) ...[
                  if (i > 0)
                    Divider(
                      indent: AppSpacing.md + AppSizes.iconBadge + 12,
                      endIndent: AppSpacing.md,
                    ),
                  StaggeredListItem(
                    index: i,
                    child: InkWell(
                      onTap: () => onTap(a),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.xs,
                          AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            CategoryIcon(
                              category: type.name,
                              icon: _typeIcon(type),
                              color: color,
                            ),
                            const SizedBox(width: AppSpacing.md - 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.account.name,
                                    style: text.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (a.account.isDefault)
                                    Text(
                                      'Default account',
                                      style: text.labelSmall?.copyWith(
                                        color: p.savings,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  formatMoney(
                                    a.account.currentValuePaise ?? a.balance,
                                    currency,
                                  ),
                                  style: text.moneyStyle(15),
                                ),
                                if (a.account.currentValuePaise != null)
                                  _GainLossLabel(
                                    invested: a.balance,
                                    current: a.account.currentValuePaise!,
                                    currency: currency,
                                  ),
                              ],
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Account options',
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: p.textTertiary,
                              ),
                              onSelected: (v) {
                                if (v == 'edit') {
                                  onEdit(a);
                                } else if (v == 'default') {
                                  onSetDefault(a);
                                } else if (v == 'delete') {
                                  onDelete(a);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                if (!a.account.isDefault)
                                  const PopupMenuItem(
                                    value: 'default',
                                    child: Text('Set as default'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The gain or loss on an investment — invested vs. current value — shown
/// as a small coloured delta under the balance.
class _GainLossLabel extends StatelessWidget {
  /// Both in paise.
  final int invested;
  final int current;
  final String currency;

  const _GainLossLabel({
    required this.invested,
    required this.current,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final delta = current - invested;
    if (delta == 0) return const SizedBox();
    final pct = invested != 0 ? (delta / invested * 100).abs() : 0;
    final up = delta > 0;
    return Text(
      '${up ? '▲' : '▼'} ${formatMoney(delta.abs(), currency)} (${pct.toStringAsFixed(1)}%)',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: up ? context.palette.income : context.palette.expense,
      ),
    );
  }
}

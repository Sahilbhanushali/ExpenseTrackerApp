import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/staggered_list.dart';
import '../../data/models/account.dart';
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
      final balance =
          double.tryParse(balanceController.text.replaceAll(',', '')) ?? 0;
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
          ? double.tryParse(currentValueController.text.replaceAll(',', ''))
          : null;
      await controller.add(
        name,
        balance,
        type: type,
        currentValue: currentValue,
      );
    }
  }

  Future<void> _showEditAccount(BuildContext context, AccountBalance a) async {
    final nameController = TextEditingController(text: a.account.name);
    final balanceController = TextEditingController(
      text: a.account.openingBalance.toStringAsFixed(0),
    );
    final currentValueController = TextEditingController(
      text: a.account.currentValue?.toStringAsFixed(0) ?? '',
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
    final balance = double.tryParse(balanceController.text.replaceAll(',', ''));
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
        ? double.tryParse(currentValueController.text.replaceAll(',', ''))
        : null;
    await controller.update(
      a.account.id!,
      name: name,
      openingBalance: balance,
      type: type,
      currentValue: currentValue,
    );
  }

  Future<void> _confirmDelete(BuildContext context, AccountBalance a) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this account?'),
        content: Text(
          '"${a.account.name}" will be removed. Transactions already logged against it are kept but will no longer show a balance here.',
        ),
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
    if (confirmed == true && context.mounted) {
      await context.read<AccountsController>().remove(a.account.id!);
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
      final amount = double.tryParse(amountController.text.replaceAll(',', ''));
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

          final amount =
              double.tryParse(amountController.text.replaceAll(',', '')) ?? 0;
          final minKeep =
              double.tryParse(minKeepController.text.replaceAll(',', '')) ?? 0;
          final available = (amount - minKeep).clamp(0, double.infinity);
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
                    'Available to split: ${formatMoney(available.toDouble(), currency)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: available <= 0 && amount > 0
                          ? AppColors.expense
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
                          ?.copyWith(color: AppColors.expense),
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
                              available *
                                  (double.tryParse(
                                        pctControllers[t.account.name]!.text,
                                      ) ??
                                      0) /
                                  100,
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
                      color: totalPct > 100 ? AppColors.expense : null,
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
                          final share = available * pct / 100;
                          if (share > 0) {
                            await controller.transfer(
                              source,
                              t.account.name,
                              share.toDouble(),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_split),
            tooltip: 'Distribute income',
            onPressed: () =>
                _showDistribute(context, accounts.accounts, currency),
          ),
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer',
            onPressed: () => _showTransfer(context, names),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'accounts_add',
        onPressed: () => _showAddAccount(context),
        child: const Icon(Icons.add),
      ),
      body: accounts.accounts.isEmpty
          ? const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: 'No accounts yet. Add one to track balances.',
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                for (final type in AccountType.values)
                  if (accounts.accounts.any((a) => a.account.type == type))
                    _AccountTypeSection(
                      type: type,
                      accounts: accounts.accounts
                          .where((a) => a.account.type == type)
                          .toList(),
                      currency: currency,
                      onTap: (a) => _showEditAccount(context, a),
                      onSetDefault: (a) => context
                          .read<AccountsController>()
                          .setDefault(a.account.name),
                      onDelete: (a) => _confirmDelete(context, a),
                    ),
              ],
            ),
    );
  }
}

class _AccountTypeSection extends StatelessWidget {
  final AccountType type;
  final List<AccountBalance> accounts;
  final String currency;
  final ValueChanged<AccountBalance> onTap;
  final ValueChanged<AccountBalance> onSetDefault;
  final ValueChanged<AccountBalance> onDelete;

  const _AccountTypeSection({
    required this.type,
    required this.accounts,
    required this.currency,
    required this.onTap,
    required this.onSetDefault,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final total = accounts.fold<double>(
      0,
      (s, a) => s + (a.account.currentValue ?? a.balance),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(_typeIcon(type), size: 18),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _typeLabel(type),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              Text(
                formatMoney(total, currency),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, a) in accounts.indexed) ...[
            StaggeredListItem(
              index: i,
              child: AppCard(
                child: PressScale(
                  onTap: () => onTap(a),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                a.account.name,
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (a.account.isDefault) ...[
                              const SizedBox(width: AppSpacing.sm),
                              const Chip(
                                label: Text('default'),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatMoney(
                              a.account.currentValue ?? a.balance,
                              currency,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (a.account.currentValue != null)
                            _GainLossLabel(
                              invested: a.balance,
                              current: a.account.currentValue!,
                              currency: currency,
                            ),
                        ],
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (v) {
                          if (v == 'default') {
                            onSetDefault(a);
                          } else if (v == 'delete') {
                            onDelete(a);
                          }
                        },
                        itemBuilder: (context) => [
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
            if (a != accounts.last) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// The gain or loss on an investment — invested vs. current value — shown
/// as a small colored delta under the balance instead of leaving the user
/// to do that subtraction themselves.
class _GainLossLabel extends StatelessWidget {
  final double invested;
  final double current;
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
      '${up ? '+' : '-'}${formatMoney(delta.abs(), currency)} (${pct.toStringAsFixed(1)}%)',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: up ? AppColors.income : AppColors.expense,
      ),
    );
  }
}

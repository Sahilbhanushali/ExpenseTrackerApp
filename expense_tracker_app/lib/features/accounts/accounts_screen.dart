import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../settings/settings_controller.dart';
import 'accounts_controller.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  Future<void> _showAddAccount(BuildContext context) async {
    final nameController = TextEditingController();
    final balanceController = TextEditingController(text: '0');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
              decoration: const InputDecoration(labelText: 'Opening balance'),
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
            child: const Text('Add'),
          ),
        ],
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
      await controller.add(name, balance);
    }
  }

  Future<void> _showEditAccount(BuildContext context, AccountBalance a) async {
    final nameController = TextEditingController(text: a.account.name);
    final balanceController = TextEditingController(
      text: a.account.openingBalance.toStringAsFixed(0),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
              decoration: const InputDecoration(labelText: 'Opening balance'),
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
    await controller.update(a.account.id!, name: name, openingBalance: balance);
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
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer',
            onPressed: () => _showTransfer(context, names),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAccount(context),
        child: const Icon(Icons.add),
      ),
      body: accounts.accounts.isEmpty
          ? const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              message: 'No accounts yet. Add one to track balances.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: accounts.accounts.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final a = accounts.accounts[i];
                return AppCard(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _showEditAccount(context, a),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  a.account.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
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
                        Text(
                          formatMoney(a.balance, currency),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (v) {
                            if (v == 'default') {
                              context.read<AccountsController>().setDefault(
                                a.account.name,
                              );
                            } else if (v == 'delete') {
                              _confirmDelete(context, a);
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
                );
              },
            ),
    );
  }
}

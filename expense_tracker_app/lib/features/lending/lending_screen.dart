import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/transaction.dart';
import '../settings/settings_controller.dart';
import 'lending_controller.dart';

class LendingScreen extends StatelessWidget {
  const LendingScreen({super.key});

  Future<void> _showLendBorrow(BuildContext context, TxnType type) async {
    final amountController = TextEditingController();
    final personController = TextEditingController();
    final noteController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(type == TxnType.lent ? 'Lend money' : 'Borrow money'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: personController, decoration: const InputDecoration(labelText: 'Person')),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );
    if (result == true && context.mounted) {
      final amount = double.tryParse(amountController.text.replaceAll(',', ''));
      final person = personController.text.trim();
      if (amount == null || amount <= 0 || person.isEmpty) return;
      final note = noteController.text.trim().isEmpty ? null : noteController.text.trim();
      final controller = context.read<LendingController>();
      if (type == TxnType.lent) {
        await controller.lend(amount, person, note);
      } else {
        await controller.borrow(amount, person, note);
      }
    }
  }

  Future<void> _showRepay(BuildContext context, Transaction loan) async {
    final amountController = TextEditingController();
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${loan.counterparty}'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Repayment amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 'settle'), child: const Text('Settle fully')),
          FilledButton(onPressed: () => Navigator.pop(context, 'repay'), child: const Text('Apply repayment')),
        ],
      ),
    );
    if (!context.mounted) return;
    final controller = context.read<LendingController>();
    if (action == 'settle') {
      await controller.settle(loan.id!);
    } else if (action == 'repay') {
      final amount = double.tryParse(amountController.text.replaceAll(',', ''));
      if (amount == null || amount <= 0) return;
      await controller.repay(loan.id!, amount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lending = context.watch<LendingController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Owed')),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'lend',
            onPressed: () => _showLendBorrow(context, TxnType.lent),
            label: const Text('Lend'),
            icon: const Icon(Icons.upload_outlined),
          ),
          const SizedBox(width: AppSpacing.sm),
          FloatingActionButton.extended(
            heroTag: 'borrow',
            onPressed: () => _showLendBorrow(context, TxnType.borrowed),
            label: const Text('Borrow'),
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: lending.outstanding.isEmpty
          ? const EmptyState(icon: Icons.handshake_outlined, message: 'Nothing outstanding — all settled up!')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 96),
              itemCount: lending.outstanding.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final r = lending.outstanding[i];
                final owesYou = r.type == TxnType.lent;
                return AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _showRepay(context, r),
                    title: Text(r.counterparty ?? 'Someone'),
                    subtitle: Text(owesYou ? 'owes you' : 'you owe'),
                    trailing: Text(
                      formatMoney(r.amount, currency),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: owesYou ? AppColors.income : AppColors.expense,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

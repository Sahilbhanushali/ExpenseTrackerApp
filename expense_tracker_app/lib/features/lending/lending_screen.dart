import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/staggered_list.dart';
import '../../data/models/loan_payment.dart';
import '../../data/models/transaction.dart';
import '../accounts/accounts_controller.dart';
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
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: personController,
              decoration: const InputDecoration(labelText: 'Person'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
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
    if (result == true && context.mounted) {
      final amount = parseRupeesToPaise(amountController.text);
      final person = personController.text.trim();
      if (amount == null || amount <= 0 || person.isEmpty) return;
      final note = noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim();
      final controller = context.read<LendingController>();
      if (type == TxnType.lent) {
        await controller.lend(amount, person, note);
      } else {
        await controller.borrow(amount, person, note);
      }
      if (context.mounted) await context.read<AccountsController>().refresh();
    }
  }

  Future<void> _showRepay(BuildContext context, Transaction loan) async {
    final amountController = TextEditingController();
    final owesYou = loan.type == TxnType.lent;
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loan.counterparty ?? 'Someone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              owesYou ? 'Owes you' : 'You owe',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'settle'),
            child: const Text('Settle fully'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'plan'),
                child: const Text('Repeat monthly'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'repay'),
                child: const Text('Apply once'),
              ),
            ],
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    final controller = context.read<LendingController>();
    if (action == 'settle') {
      await controller.settle(loan.id!);
      if (context.mounted) await context.read<AccountsController>().refresh();
    } else if (action == 'repay') {
      final amount = parseRupeesToPaise(amountController.text);
      if (amount == null || amount <= 0) return;
      await controller.repay(loan.id!, amount);
      if (context.mounted) await context.read<AccountsController>().refresh();
    } else if (action == 'plan') {
      final amount = parseRupeesToPaise(amountController.text);
      if (amount == null || amount <= 0) return;
      await _showMonthlyPlan(context, loan, amount);
    }
  }

  Future<void> _showMonthlyPlan(
    BuildContext context,
    Transaction loan,
    int amountPaise,
  ) async {
    final currency = context.read<SettingsController>().config.currency;
    final dayController = TextEditingController(text: '${DateTime.now().day}');
    final monthsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repeat monthly'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${formatMoney(amountPaise, currency)} every month toward ${loan.counterparty ?? 'them'}, reminded automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: dayController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Day of month (1-28)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: monthsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of months (optional)',
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
            child: const Text('Schedule'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final day = (int.tryParse(dayController.text) ?? DateTime.now().day).clamp(
      1,
      28,
    );
    final months = int.tryParse(monthsController.text);
    await context.read<LendingController>().repayPlan(
      loan.id!,
      amountPaise,
      months: months,
      dayOfMonth: day,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Monthly repayment of ${formatMoney(amountPaise, currency)} scheduled on day $day — log it from Recurring & EMI when due.',
        ),
      ),
    );
  }

  Future<void> _showHistory(BuildContext context, Transaction loan) async {
    final controller = context.read<LendingController>();
    final currency = context.read<SettingsController>().config.currency;
    final payments = await controller.paymentHistory(loan.id!);
    if (!context.mounted) return;
    final original = controller.originalAmount(loan, payments);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${loan.counterparty ?? 'Someone'} — payment history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              BudgetProgressBar(
                spent: original - loan.amountPaise,
                budget: original,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatMoney(original - loan.amountPaise, currency)} paid of ${formatMoney(original, currency)} · ${formatMoney(loan.amountPaise, currency)} left',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: payments.isEmpty
                    ? Center(
                        child: Text(
                          'No installments logged yet.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: payments.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (context, i) => _PaymentRow(
                          payment: payments[i],
                          currency: currency,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showEditLoan(BuildContext context, Transaction loan) async {
    final amountController = TextEditingController(
      text: paiseToEditString(loan.amountPaise),
    );
    final personController = TextEditingController(
      text: loan.counterparty ?? '',
    );
    final noteController = TextEditingController(text: loan.note ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          loan.type == TxnType.lent ? 'Edit loan' : 'Edit borrowed amount',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: personController,
              decoration: const InputDecoration(labelText: 'Person'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
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
    final amount = parseRupeesToPaise(amountController.text);
    final person = personController.text.trim();
    if (amount == null || amount <= 0 || person.isEmpty) return;
    final note = noteController.text.trim().isEmpty
        ? null
        : noteController.text.trim();
    await context.read<LendingController>().update(
      loan.id!,
      amountPaise: amount,
      person: person,
      note: note,
    );
    if (context.mounted) await context.read<AccountsController>().refresh();
  }

  Future<void> _confirmDeleteLoan(
    BuildContext context,
    Transaction loan,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text(
          'This removes the record with ${loan.counterparty ?? 'them'} entirely.',
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
      await context.read<LendingController>().remove(loan.id!);
      if (context.mounted) await context.read<AccountsController>().refresh();
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
          ? const EmptyState(
              icon: Icons.handshake_outlined,
              message: 'Nothing outstanding — all settled up!',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                96,
              ),
              itemCount: lending.outstanding.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final r = lending.outstanding[i];
                final owesYou = r.type == TxnType.lent;
                return StaggeredListItem(
                  index: i,
                  child: AppCard(
                    child: ListRow(
                      icon: owesYou
                          ? Icons.upload_outlined
                          : Icons.download_outlined,
                      iconColor: owesYou ? AppColors.income : AppColors.expense,
                      title: r.counterparty ?? 'Someone',
                      subtitle: owesYou ? 'owes you' : 'you owe',
                      onTap: () => _showRepay(context, r),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMoney(r.amountPaise, currency),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: owesYou
                                  ? AppColors.income
                                  : AppColors.expense,
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (v) {
                              if (v == 'history') {
                                _showHistory(context, r);
                              } else if (v == 'edit') {
                                _showEditLoan(context, r);
                              } else if (v == 'delete') {
                                _confirmDeleteLoan(context, r);
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'history',
                                child: Text('Payment history'),
                              ),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final LoanPayment payment;
  final String currency;

  const _PaymentRow({required this.payment, required this.currency});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(payment.date, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            formatMoney(payment.amountPaise, currency),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

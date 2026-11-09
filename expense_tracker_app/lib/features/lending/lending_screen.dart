import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/form_sheet.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
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
    final result = await showFormSheet(
      context,
      title: Text(type == TxnType.lent ? 'Lend money' : 'Borrow money'),
      submitLabel: 'Save',
      validate: () =>
          requireText(personController.text, 'a name') ??
          positiveAmountError(amountController.text),
      builder: (context, setState) => Column(
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
    final confirmed = await showFormSheet(
      context,
      title: const Text('Repeat monthly'),
      submitLabel: 'Schedule',
      builder: (context, setState) => Column(
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
            decoration: const InputDecoration(labelText: 'Day of month (1-28)'),
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
    final left = controller.remaining(loan);

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
              BudgetProgressBar(spent: original - left, budget: original),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatMoney(original - left, currency)} paid of ${formatMoney(original, currency)} · ${formatMoney(left, currency)} left',
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
    final result = await showFormSheet(
      context,
      title: Text(
        loan.type == TxnType.lent ? 'Edit loan' : 'Edit borrowed amount',
      ),
      submitLabel: 'Save',
      validate: () =>
          requireText(personController.text, 'a name') ??
          positiveAmountError(amountController.text),
      builder: (context, setState) => Column(
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
    final owedToYou = lending.totalOutstanding(TxnType.lent);
    final youOwe = lending.totalOutstanding(TxnType.borrowed);

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
              title: 'All settled up',
              message: 'Use Lend or Borrow to track money between friends.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              itemCount: lending.outstanding.length + 1,
              separatorBuilder: (_, i) =>
                  SizedBox(height: i == 0 ? AppSpacing.lg : AppSpacing.sm),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _OwedSummary(
                    owedToYou: owedToYou,
                    youOwe: youOwe,
                    currency: currency,
                  );
                }
                final i = index - 1;
                final r = lending.outstanding[i];
                final owesYou = r.type == TxnType.lent;
                return StaggeredListItem(
                  index: i,
                  child: AppCard(
                    child: ListRow(
                      icon: owesYou
                          ? Icons.upload_outlined
                          : Icons.download_outlined,
                      iconColor: owesYou
                          ? context.palette.income
                          : context.palette.expense,
                      title: r.counterparty ?? 'Someone',
                      subtitle: owesYou ? 'owes you' : 'you owe',
                      onTap: () => _showRepay(context, r),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatMoney(lending.remaining(r), currency),
                            style: Theme.of(context).textTheme.moneyStyle(
                              15,
                              color: owesYou
                                  ? context.palette.income
                                  : context.palette.expense,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Options',
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: context.palette.textTertiary,
                            ),
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

class _OwedSummary extends StatelessWidget {
  final int owedToYou;
  final int youOwe;
  final String currency;

  const _OwedSummary({
    required this.owedToYou,
    required this.youOwe,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    Widget tile(String label, int value, Color color, IconData icon) =>
        Expanded(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: AppIconSize.sm, color: color),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(child: Text(label, style: text.bodySmall)),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatMoney(value, currency),
                    style: text.moneyStyle(20, color: color),
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('Owed to you', owedToYou, p.income, Icons.call_received_rounded),
        const SizedBox(width: AppSpacing.sm),
        tile('You owe', youOwe, p.expense, Icons.call_made_rounded),
      ],
    );
  }
}

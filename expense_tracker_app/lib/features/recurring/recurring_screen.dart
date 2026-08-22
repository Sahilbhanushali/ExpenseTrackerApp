import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/recurring_bill.dart';
import '../settings/settings_controller.dart';
import 'recurring_controller.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  Future<void> _showAddBill(BuildContext context, {bool isEmi = false}) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final dayController = TextEditingController(text: '${DateTime.now().day}');
    final monthsController = TextEditingController(text: '3');
    String category = kDefaultCategory;
    final categories = [...kCategoryKeywords.keys, kDefaultCategory];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEmi ? 'Log EMI installment' : 'Add recurring bill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Monthly amount',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => category = v ?? kDefaultCategory),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: dayController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: isEmi ? 'Due day (1-28)' : 'Day of month (1-28)',
                  ),
                ),
                if (isEmi) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: monthsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Total months',
                    ),
                  ),
                ],
              ],
            ),
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
    final amount = double.tryParse(amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final note = noteController.text.trim().isEmpty
        ? null
        : noteController.text.trim();
    final day = (int.tryParse(dayController.text) ?? DateTime.now().day).clamp(
      1,
      28,
    );
    final controller = context.read<RecurringController>();

    if (isEmi) {
      final months = int.tryParse(monthsController.text) ?? 1;
      await controller.logEmi(
        monthlyAmount: amount,
        category: category,
        note: note,
        months: months,
        dueDay: day,
      );
    } else {
      await controller.addBill(
        amount: amount,
        category: category,
        note: note,
        dayOfMonth: day,
      );
    }
  }

  Future<void> _showAddSalary(BuildContext context) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController(text: 'Salary');
    final dayController = TextEditingController(text: '${DateTime.now().day}');

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add recurring income'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Source (e.g. Salary)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: dayController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Pay day (1-28)'),
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
    final amount = double.tryParse(amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final note = noteController.text.trim().isEmpty
        ? 'Salary'
        : noteController.text.trim();
    final day = (int.tryParse(dayController.text) ?? DateTime.now().day).clamp(
      1,
      28,
    );

    await context.read<RecurringController>().addBill(
      amount: amount,
      category: 'income',
      note: note,
      dayOfMonth: day,
      type: RecurringType.income,
    );
  }

  Future<void> _showEditBill(BuildContext context, RecurringBill bill) async {
    final isIncome = bill.type == RecurringType.income;
    final amountController = TextEditingController(
      text: bill.amount.toStringAsFixed(0),
    );
    final noteController = TextEditingController(text: bill.note ?? '');
    final dayController = TextEditingController(text: '${bill.dayOfMonth}');
    String category = bill.category;
    final categories = [...kCategoryKeywords.keys, kDefaultCategory];

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isIncome ? 'Edit income' : 'Edit recurring bill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!isIncome && bill.loanId == null)
                  DropdownButtonFormField<String>(
                    initialValue: categories.contains(category)
                        ? category
                        : kDefaultCategory,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => category = v ?? kDefaultCategory),
                  ),
                if (!isIncome && bill.loanId == null)
                  const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: isIncome ? 'Source' : 'Note',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: dayController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Day of month (1-28)',
                  ),
                ),
              ],
            ),
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
    final amount = double.tryParse(amountController.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) return;
    final note = noteController.text.trim().isEmpty
        ? null
        : noteController.text.trim();
    final day = (int.tryParse(dayController.text) ?? bill.dayOfMonth).clamp(
      1,
      28,
    );

    await context.read<RecurringController>().update(
      bill.id!,
      amount: amount,
      category: bill.loanId == null && !isIncome ? category : null,
      note: note,
      dayOfMonth: day,
    );
  }

  Future<void> _confirmDelete(BuildContext context, RecurringBill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this reminder?'),
        content: const Text(
          'This stops future auto-reminders. Already-logged transactions are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<RecurringController>().remove(bill.id!);
    }
  }

  Future<void> _logDueNow(BuildContext context, RecurringBill bill) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await context.read<RecurringController>().logDue(bill);
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final recurring = context.watch<RecurringController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring & EMI')),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'salary',
            onPressed: () => _showAddSalary(context),
            label: const Text('Salary'),
            icon: const Icon(Icons.savings_outlined),
            backgroundColor: AppColors.income,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'emi',
                onPressed: () => _showAddBill(context, isEmi: true),
                label: const Text('EMI'),
                icon: const Icon(Icons.credit_card_outlined),
              ),
              const SizedBox(width: AppSpacing.sm),
              FloatingActionButton.extended(
                heroTag: 'bill',
                onPressed: () => _showAddBill(context),
                label: const Text('Bill'),
                icon: const Icon(Icons.event_repeat_outlined),
              ),
            ],
          ),
        ],
      ),
      body: recurring.bills.isEmpty
          ? const EmptyState(
              icon: Icons.event_repeat_outlined,
              message: 'No recurring bills or income set up yet.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                140,
              ),
              children: [
                if (recurring.due.isNotEmpty) ...[
                  Text(
                    'Due now',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...recurring.due.map((r) {
                    final isIncome = r.type == RecurringType.income;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        child: Row(
                          children: [
                            Icon(
                              isIncome
                                  ? Icons.savings_outlined
                                  : Icons.event_repeat_outlined,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${isIncome ? r.note ?? 'Income' : r.category} · ${formatMoney(r.amount, currency)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                  Text(
                                    'Was due on day ${r.dayOfMonth}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: () => _logDueNow(context, r),
                              child: const Text('Log now'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'All recurring',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                ...recurring.bills.map((r) {
                  final remaining = r.installmentsRemaining;
                  final isIncome = r.type == RecurringType.income;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        onTap: () => _showEditBill(context, r),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isIncome
                                ? Icons.savings_outlined
                                : Icons.event_repeat_outlined,
                            color: isIncome ? AppColors.income : null,
                          ),
                          title: Text(
                            '${isIncome ? r.note ?? 'Income' : r.category} · '
                            '${isIncome ? '+' : ''}${formatMoney(r.amount, currency)}',
                            style: isIncome
                                ? const TextStyle(color: AppColors.income)
                                : null,
                          ),
                          subtitle: Text(
                            'Day ${r.dayOfMonth}${!isIncome && r.note?.isNotEmpty == true ? ' · ${r.note}' : ''}${remaining != null ? ' · $remaining left' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, r),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

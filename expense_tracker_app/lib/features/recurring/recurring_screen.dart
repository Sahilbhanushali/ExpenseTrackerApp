import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/widgets/form_sheet.dart';
import '../../core/constants/categories.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/list_row.dart';
import '../../core/widgets/staggered_list.dart';
import '../../data/models/recurring_bill.dart';
import '../accounts/accounts_controller.dart';
import '../settings/settings_controller.dart';
import '../loans/loans_screen.dart';
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

    final result = await showFormSheet(
      context,
      title: Text(isEmi ? 'Log EMI installment' : 'Add recurring bill'),
      submitLabel: 'Save',
      validate: () => positiveAmountError(amountController.text),
      builder: (context, setState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Monthly amount'),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => category = v ?? kDefaultCategory),
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
              decoration: const InputDecoration(labelText: 'Total months'),
            ),
          ],
        ],
      ),
    );

    if (result != true || !context.mounted) return;
    final amount = parseRupeesToPaise(amountController.text);
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
        monthlyPaise: amount,
        category: category,
        note: note,
        months: months,
        dueDay: day,
      );
      if (context.mounted) await context.read<AccountsController>().refresh();
    } else {
      await controller.addBill(
        amountPaise: amount,
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

    final result = await showFormSheet(
      context,
      title: const Text('Add recurring income'),
      submitLabel: 'Save',
      validate: () => positiveAmountError(amountController.text),
      builder: (context, setState) => Column(
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
    );

    if (result != true || !context.mounted) return;
    final amount = parseRupeesToPaise(amountController.text);
    if (amount == null || amount <= 0) return;
    final note = noteController.text.trim().isEmpty
        ? 'Salary'
        : noteController.text.trim();
    final day = (int.tryParse(dayController.text) ?? DateTime.now().day).clamp(
      1,
      28,
    );

    await context.read<RecurringController>().addBill(
      amountPaise: amount,
      category: 'income',
      note: note,
      dayOfMonth: day,
      type: RecurringType.income,
    );
  }

  Future<void> _showEditBill(BuildContext context, RecurringBill bill) async {
    final isIncome = bill.type == RecurringType.income;
    final amountController = TextEditingController(
      text: paiseToEditString(bill.amountPaise),
    );
    final noteController = TextEditingController(text: bill.note ?? '');
    final dayController = TextEditingController(text: '${bill.dayOfMonth}');
    String category = bill.category;
    final categories = [...kCategoryKeywords.keys, kDefaultCategory];

    final result = await showFormSheet(
      context,
      title: Text(isIncome ? 'Edit income' : 'Edit recurring bill'),
      submitLabel: 'Save',
      validate: () => positiveAmountError(amountController.text),
      builder: (context, setState) => Column(
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
            decoration: const InputDecoration(labelText: 'Day of month (1-28)'),
          ),
        ],
      ),
    );

    if (result != true || !context.mounted) return;
    final amount = parseRupeesToPaise(amountController.text);
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
      amountPaise: amount,
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
    if (context.mounted) await context.read<AccountsController>().refresh();
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final recurring = context.watch<RecurringController>();
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring bills')),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'salary',
            onPressed: () => _showAddSalary(context),
            label: const Text('Salary'),
            icon: const Icon(Icons.savings_outlined),
            backgroundColor: context.palette.income,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.extended(
                heroTag: 'emi',
                // EMIs live in Loans & EMI, with a schedule and the
                // principal/interest split — one EMI system, not two.
                onPressed: () => showLoanForm(context),
                label: const Text('Loan / EMI'),
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
              // Clears the stacked FABs.
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance + AppSpacing.xl,
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
                              color: context.palette.warning,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${isIncome ? r.note ?? 'Income' : r.category} · ${formatMoney(r.amountPaise, currency)}',
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
                ...recurring.bills.indexed.map((entry) {
                  final (i, r) = entry;
                  final remaining = r.installmentsRemaining;
                  final isIncome = r.type == RecurringType.income;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: StaggeredListItem(
                      index: i,
                      child: AppCard(
                        child: ListRow(
                          icon: isIncome
                              ? Icons.savings_outlined
                              : Icons.event_repeat_outlined,
                          iconColor: isIncome ? context.palette.income : null,
                          title:
                              '${isIncome ? r.note ?? 'Income' : r.category} · '
                              '${isIncome ? '+' : ''}${formatMoney(r.amountPaise, currency)}',
                          titleStyle: isIncome
                              ? TextStyle(color: context.palette.income)
                              : null,
                          subtitle:
                              'Day ${r.dayOfMonth}${!isIncome && r.note?.isNotEmpty == true ? ' · ${r.note}' : ''}${remaining != null ? ' · $remaining left' : ''}',
                          onTap: () => _showEditBill(context, r),
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

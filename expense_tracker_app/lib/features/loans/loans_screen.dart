import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../data/models/loan.dart';
import '../accounts/accounts_controller.dart';
import '../settings/settings_controller.dart';
import 'loans_controller.dart';

class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  /// Add when [existing] is null, edit otherwise. Editing matters as much
  /// as adding: a bank's real EMI schedule rarely matches what you guessed
  /// when you first entered it, and a wrong start date or paid count throws
  /// off every due date and the outstanding balance.
  Future<void> _showLoanEditor(BuildContext context, {Loan? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final principalController = TextEditingController(
      text: existing != null ? paiseToEditString(existing.principalPaise) : '',
    );
    final interestController = TextEditingController(
      text: existing != null ? paiseToEditString(existing.interestPaise) : '0',
    );
    final emiController = TextEditingController(
      text: existing != null ? paiseToEditString(existing.emiPaise) : '',
    );
    final tenureController = TextEditingController(
      text: existing != null ? '${existing.tenureMonths}' : '',
    );
    final paidController = TextEditingController(
      text: '${existing?.installmentsPaid ?? 0}',
    );
    DateTime startDate = existing?.startDate ?? DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Add loan / EMI' : 'Edit loan / EMI'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name (e.g. Card EMI - Fridge)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: principalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Loan amount (principal)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: interestController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Total interest',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: emiController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Monthly EMI amount',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: tenureController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tenure (months)',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start date'),
                  subtitle: Text(
                    '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: startDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => startDate = picked);
                  },
                ),
                if (existing != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: paidController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Installments already paid',
                      helperText: 'of ${existing.tenureMonths}',
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
    final name = nameController.text.trim();
    final principal = parseRupeesToPaise(principalController.text);
    final interest = parseRupeesToPaise(interestController.text) ?? 0;
    final emi = parseRupeesToPaise(emiController.text);
    final tenure = int.tryParse(tenureController.text);
    if (name.isEmpty ||
        principal == null ||
        emi == null ||
        tenure == null ||
        tenure <= 0) {
      return;
    }

    final controller = context.read<LoansController>();
    if (existing == null) {
      await controller.addLoan(
        name: name,
        principalPaise: principal,
        interestPaise: interest,
        emiPaise: emi,
        tenureMonths: tenure,
        startDate: startDate,
      );
    } else {
      await controller.update(
        existing.id!,
        name: name,
        principalPaise: principal,
        interestPaise: interest,
        emiPaise: emi,
        tenureMonths: tenure,
        installmentsPaid: (int.tryParse(paidController.text) ?? 0).clamp(
          0,
          tenure,
        ),
        startDate: startDate,
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, Loan loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this loan?'),
        content: const Text(
          'This stops tracking it here. Already-logged EMI payments are unaffected.',
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
      await context.read<LoansController>().remove(loan.id!);
    }
  }

  Future<void> _payInstallment(BuildContext context, Loan loan) async {
    final messenger = ScaffoldMessenger.of(context);
    final finished = await context.read<LoansController>().payInstallment(loan);
    if (context.mounted) await context.read<AccountsController>().refresh();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          finished
              ? '${loan.name} — final installment paid, loan closed!'
              : 'Logged EMI for ${loan.name}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loans = context.watch<LoansController>().loans;
    final currency = context.watch<SettingsController>().config.currency;

    return Scaffold(
      appBar: AppBar(title: const Text('Loans & EMI')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'loans_add',
        onPressed: () => _showLoanEditor(context),
        label: const Text('Add loan'),
        icon: const Icon(Icons.account_balance_outlined),
      ),
      body: loans.isEmpty
          ? const EmptyState(
              icon: Icons.account_balance_outlined,
              message: 'No loans or interest-bearing EMIs tracked yet.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.navClearance,
              ),
              itemCount: loans.length,
              itemBuilder: (context, index) => _LoanCard(
                loan: loans[index],
                currency: currency,
                onPay: () => _payInstallment(context, loans[index]),
                onEdit: () => _showLoanEditor(context, existing: loans[index]),
                onDelete: () => _confirmDelete(context, loans[index]),
              ),
            ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  final Loan loan;
  final String currency;
  final VoidCallback onPay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LoanCard({
    required this.loan,
    required this.currency,
    required this.onPay,
    required this.onEdit,
    required this.onDelete,
  });

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')} ${_month[d.month - 1]} ${d.year}';

  static const _month = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final progress = loan.tenureMonths == 0
        ? 0.0
        : (loan.installmentsPaid / loan.tenureMonths).clamp(0.0, 1.0);
    final nextDue = loan.nextDueDate;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loan.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (loan.isFullyPaid) const Chip(label: Text('Paid off')),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit loan',
                  onPressed: onEdit,
                ),
                if (!loan.isFullyPaid)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Remove loan',
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Outstanding',
                    value: formatMoney(loan.outstandingPaise, currency),
                    color: context.palette.expense,
                    emphasize: true,
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Total payable',
                    value: formatMoney(loan.totalPayablePaise, currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Principal',
                    value: formatMoney(loan.principalPaise, currency),
                  ),
                ),
                Expanded(
                  child: _Stat(
                    label: 'Interest',
                    value: formatMoney(loan.interestPaise, currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: context.palette.savings.withValues(
                  alpha: 0.15,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${loan.installmentsPaid}/${loan.tenureMonths} EMIs paid · '
              '${loan.installmentsRemaining} remaining',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    label: 'Started',
                    value: _fmtDate(loan.startDate),
                  ),
                ),
                Expanded(
                  child: _Stat(label: 'Ends', value: _fmtDate(loan.endDate)),
                ),
              ],
            ),
            if (nextDue != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: context.palette.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_outlined,
                      size: 18,
                      color: context.palette.warning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Next EMI: ${formatMoney(loan.emiPaise, currency)} '
                        'on ${_fmtDate(nextDue)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: onPay,
                      child: const Text('Pay now'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool emphasize;

  const _Stat({
    required this.label,
    required this.value,
    this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style:
              (emphasize
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.bodyMedium)
                  ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

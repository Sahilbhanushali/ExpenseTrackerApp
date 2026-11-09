import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/finance/loans.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../data/models/account.dart';
import '../../data/models/loan.dart';
import '../../data/repositories/loan_repository.dart';
import '../accounts/accounts_controller.dart';
import '../cycles/cycle_card.dart';
import '../settings/settings_controller.dart';
import 'loans_controller.dart';

String _currency(BuildContext c) =>
    c.read<SettingsController>().config.currency;

void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

/// Account names to pay from, the EMI account first.
List<String> _payFrom(BuildContext context, String? preferred) {
  final active = context.read<AccountsController>().active;
  final names = [for (final a in active) a.account.name];
  final emi = active
      .where((a) => a.account.roles.contains(AccountRole.emi))
      .map((a) => a.account.name);
  return {
    if (preferred != null && names.contains(preferred)) preferred,
    ...emi,
    ...names,
  }.toList();
}

Widget _accountField(
  List<String> names,
  String? value,
  String label,
  ValueChanged<String?> onChanged,
) => DropdownButtonFormField<String>(
  initialValue: value,
  decoration: InputDecoration(labelText: label),
  items: [for (final n in names) DropdownMenuItem(value: n, child: Text(n))],
  onChanged: onChanged,
);

class LoansScreen extends StatelessWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final loans = context.watch<LoansController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final active = loans.active;
    final closed = loans.loans.where((l) => l.closed).toList();
    final nextDue = active
        .map((l) => l.next)
        .whereType<LoanInstallment>()
        .fold<LoanInstallment?>(
          null,
          (a, b) => a == null || b.dueDate.isBefore(a.dueDate) ? b : a,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Loans & EMI')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_loan',
        onPressed: () => showLoanForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add loan'),
      ),
      body: ResponsivePage(
        builder: (context, gutter) => ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            AppSpacing.sm,
            gutter,
            AppSpacing.navClearance,
          ),
          children: [
            if (loans.loans.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.account_balance_outlined,
                  title: 'No loans or EMIs',
                  message:
                      'Add a personal, vehicle or home loan, or something '
                      'bought on EMI. Payments are split into principal '
                      '(lowers the debt) and interest (an expense).',
                  action: 'Add loan',
                  onAction: () => showLoanForm(context),
                ),
              )
            else ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Principal still owed', style: text.labelMedium),
                          Text(
                            formatMoney(loans.outstanding, currency),
                            style: text.moneyStyle(24, color: p.expense),
                          ),
                        ],
                      ),
                    ),
                    if (nextDue != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Next EMI', style: text.labelMedium),
                          Text(
                            formatMoney(nextDue.remaining, currency),
                            style: text.moneyStyle(16),
                          ),
                          Text(
                            shortDate(nextDue.dueDate),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final l in active)
                _LoanCard(standing: l, currency: currency),
              if (closed.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('Closed', style: text.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                for (final l in closed)
                  _LoanCard(standing: l, currency: currency),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  final LoanStanding standing;
  final String currency;
  const _LoanCard({required this.standing, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final loan = standing.loan;
    final next = standing.next;
    final total = standing.installments
        .where((i) => i.status != 'cancelled')
        .length;
    final overdue =
        next != null && next.dueDate.isBefore(dateOnly(DateTime.now()));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () =>
            Navigator.of(context)
                .push(FadeSlideRoute(page: LoanDetailScreen(loanId: loan.id!))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.name, style: text.titleSmall),
                      Text(
                        [loanKindLabel(loan.kind), ?loan.lender].join(' · '),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  standing.closed
                      ? 'Closed'
                      : formatMoney(standing.outstandingPrincipal, currency),
                  style: text.moneyStyle(16),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            BudgetProgressBar(
              spent: standing.paidCount,
              budget: total == 0 ? 1 : total,
              color: p.income,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              [
                '${standing.paidCount} of $total paid',
                if (next != null)
                  '${overdue ? 'overdue since' : 'next'} ${shortDate(next.dueDate)}: '
                      '${formatMoney(next.remaining, currency)}',
              ].join(' · '),
              style: text.bodySmall?.copyWith(
                color: overdue ? p.warning : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LoanDetailScreen extends StatelessWidget {
  final int loanId;
  const LoanDetailScreen({super.key, required this.loanId});

  Future<void> _run(
    BuildContext context,
    Future<void> Function() f,
    String done,
  ) async {
    try {
      await f();
      if (context.mounted) _snack(context, done);
    } on LoanException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _pay(BuildContext context, LoanStanding l) async {
    final next = l.next!;
    final currency = _currency(context);
    final names = _payFrom(context, l.loan.account);
    if (names.isEmpty) return _snack(context, 'Add a bank account first.');
    final amount = TextEditingController(
      text: paiseToEditString(next.remaining),
    );
    String? account = names.first;
    final ok = await showFormSheet(
      context,
      title: Text('Pay EMI ${next.seq}'),
      subtitle:
          'Interest first, then principal. Principal lowers what you owe; '
          'interest is recorded as an expense.',
      submitLabel: 'Record payment',
      validate: () {
        final e = positiveAmountError(amount.text);
        if (e != null) return e;
        return parseRupeesToPaise(amount.text)! > next.remaining
            ? 'More than this EMI. Use Prepay for the extra.'
            : null;
      },
      builder: (context, setState) {
        final paid = parseRupeesToPaise(amount.text) ?? 0;
        final split = splitPayment(
          amount: paid,
          interestDue: next.interest - next.interestPaid,
          principalDue: next.principal - next.principalPaid,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$currency ',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Interest ${formatMoney(split.interest, currency)} · '
              'Principal ${formatMoney(split.principal, currency)}'
              '${l.loan.splitEstimated ? ' (estimated split)' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md - 4),
            _accountField(
              names,
              account,
              'Paid from',
              (v) => setState(() => account = v),
            ),
          ],
        );
      },
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => context.read<LoansController>().payInstallment(
        l,
        amountPaise: parseRupeesToPaise(amount.text),
        account: account!,
      ),
      'Payment recorded.',
    );
  }

  Future<void> _prepay(BuildContext context, LoanStanding l) async {
    final names = _payFrom(context, l.loan.account);
    if (names.isEmpty) return _snack(context, 'Add a bank account first.');
    final amount = TextEditingController();
    String? account = names.first;
    var mode = PrepayMode.reduceTenure;
    final ok = await showFormSheet(
      context,
      title: const Text('Prepay principal'),
      subtitle: 'Extra paid now goes entirely to principal.',
      submitLabel: 'Prepay',
      validate: () {
        final e = positiveAmountError(amount.text);
        if (e != null) return e;
        return parseRupeesToPaise(amount.text)! > l.outstandingPrincipal
            ? 'That’s more than is owed. Use Close loan instead.'
            : null;
      },
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<PrepayMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: PrepayMode.reduceTenure,
                label: Text('Finish sooner'),
              ),
              ButtonSegment(
                value: PrepayMode.reduceEmi,
                label: Text('Lower EMI'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          _accountField(
            names,
            account,
            'Paid from',
            (v) => setState(() => account = v),
          ),
        ],
      ),
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => context.read<LoansController>().prepay(
        l,
        amountPaise: parseRupeesToPaise(amount.text)!,
        account: account!,
        mode: mode,
      ),
      'Prepayment recorded. The schedule was updated.',
    );
  }

  Future<void> _close(BuildContext context, LoanStanding l) async {
    final currency = _currency(context);
    final names = _payFrom(context, l.loan.account);
    if (names.isEmpty) return _snack(context, 'Add a bank account first.');
    final charges = TextEditingController();
    String? account = names.first;
    final ok = await showFormSheet(
      context,
      title: const Text('Close loan'),
      subtitle:
          'Pays the ${formatMoney(l.outstandingPrincipal, currency)} principal '
          'still owed. Remaining EMIs are cancelled.',
      submitLabel: 'Close loan',
      destructive: true,
      validate: () => charges.text.trim().isEmpty
          ? null
          : (parseRupeesToPaise(charges.text) ?? -1) < 0
          ? 'Enter a valid amount.'
          : null,
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: charges,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Foreclosure charges (optional)',
              helperText: 'Recorded as an expense',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          _accountField(
            names,
            account,
            'Paid from',
            (v) => setState(() => account = v),
          ),
        ],
      ),
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => context.read<LoansController>().foreclose(
        l,
        account: account!,
        chargesPaise: parseRupeesToPaise(charges.text) ?? 0,
      ),
      'Loan closed.',
    );
  }

  Future<void> _correct(BuildContext context, LoanStanding l) async {
    final amount = TextEditingController(
      text: paiseToEditString(l.outstandingPrincipal),
    );
    final note = TextEditingController();
    final ok = await showFormSheet(
      context,
      title: const Text('Correct what’s owed'),
      subtitle:
          'Match the lender’s statement. No money moves; the change is kept '
          'in the history and future EMIs are recalculated.',
      submitLabel: 'Save',
      validate: () => (parseRupeesToPaise(amount.text) ?? -1) < 0
          ? 'Enter the principal the lender shows.'
          : null,
      builder: (context, setState) => Column(
        children: [
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Principal outstanding',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
          ),
        ],
      ),
    );
    if (!ok || !context.mounted) return;
    await _run(
      context,
      () => context.read<LoansController>().correct(
        l,
        parseRupeesToPaise(amount.text)!,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      ),
      'Balance corrected.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final loans = context.watch<LoansController>();
    final l = loans.loans.where((x) => x.loan.id == loanId).firstOrNull;
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    if (l == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          message: 'This loan is gone.',
        ),
      );
    }
    final schedule = l.installments
        .where((i) => i.status != 'cancelled')
        .toList();
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(l.loan.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More actions',
            onSelected: (v) async {
              switch (v) {
                case 'correct':
                  await _correct(context, l);
                case 'undo':
                  final done = await context
                      .read<LoansController>()
                      .undoLastPayment(l);
                  if (context.mounted) {
                    _snack(
                      context,
                      done ? 'Last payment undone.' : 'No payment to undo.',
                    );
                  }
                case 'remove':
                  await _run(
                    context,
                    () => context.read<LoansController>().remove(l),
                    'Loan removed.',
                  );
                  if (context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => [
              if (!l.closed)
                const PopupMenuItem(
                  value: 'correct',
                  child: Text('Correct balance'),
                ),
              const PopupMenuItem(
                value: 'undo',
                child: Text('Undo last payment'),
              ),
              const PopupMenuItem(value: 'remove', child: Text('Remove loan')),
            ],
          ),
        ],
      ),
      body: ResponsivePage(
        builder: (context, gutter) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, AppSpacing.sm, gutter, 0),
              sliver: SliverList.list(
                children: [
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Principal still owed', style: text.labelMedium),
                        Text(
                          formatMoney(l.outstandingPrincipal, currency),
                          style: text.moneyStyle(26),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: AppSpacing.xs,
                          children: [
                            Text(
                              loanKindLabel(l.loan.kind),
                              style: text.bodySmall,
                            ),
                            Text(
                              'EMI ${formatMoney(l.loan.emiPaise, currency)}',
                              style: text.bodySmall,
                            ),
                            if (l.loan.rateBps != null)
                              Text(
                                '${(l.loan.rateBps! / 100).toStringAsFixed(2)}% a year',
                                style: text.bodySmall,
                              ),
                            Text(
                              'Interest paid ${formatMoney(l.interestPaid, currency)}',
                              style: text.bodySmall,
                            ),
                            Text(
                              'Left to pay ${formatMoney(l.remainingPayable, currency)}',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                        if (l.loan.splitEstimated)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.sm),
                            child: Text(
                              'No interest rate was given, so each EMI’s '
                              'interest/principal split is your total interest '
                              'spread evenly. Correct the balance from a lender '
                              'statement any time.',
                              style: text.bodySmall?.copyWith(color: p.warning),
                            ),
                          ),
                        if (!l.closed) ...[
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: l.next == null
                                      ? null
                                      : () => _pay(context, l),
                                  child: const Text('Pay EMI'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _prepay(context, l),
                                  child: const Text('Prepay'),
                                ),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => _close(context, l),
                            child: const Text('Close loan early'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Schedule', style: text.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, AppSpacing.xl),
              sliver: SliverList.builder(
                itemCount: schedule.length,
                itemBuilder: (context, i) {
                  final inst = schedule[i];
                  final overdue = inst.isDue && inst.dueDate.isBefore(today);
                  final (label, color) = inst.status == 'paid'
                      ? ('Paid', p.income)
                      : inst.partlyPaid
                      ? ('Part paid', p.warning)
                      : overdue
                      ? ('Overdue', p.expense)
                      : ('Due', p.textSecondary);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: AppSizes.iconBadge,
                            child: Text(
                              '#${inst.seq}',
                              style: text.labelMedium,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  shortDate(inst.dueDate),
                                  style: text.bodyMedium,
                                ),
                                Text(
                                  'Principal ${formatMoneyCompact(inst.principal, currency)} · '
                                  'Interest ${formatMoneyCompact(inst.interest, currency)}',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatMoney(inst.amount, currency),
                                style: text.moneyStyle(14),
                              ),
                              Text(
                                label,
                                style: text.labelSmall?.copyWith(color: color),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds a loan. [prefill] comes from quick-add ("bought fridge on emi
/// 3000 for 6 months").
Future<void> showLoanForm(
  BuildContext context, {
  String? name,
  int? emiPaise,
  int? months,
}) async {
  final currency = _currency(context);
  final accounts = _payFrom(context, null);
  final nameC = TextEditingController(text: name ?? '');
  final lender = TextEditingController();
  final principal = TextEditingController();
  final rate = TextEditingController();
  final tenure = TextEditingController(text: months?.toString() ?? '');
  final emi = TextEditingController(
    text: emiPaise == null ? '' : paiseToEditString(emiPaise),
  );
  var kind = name == null ? LoanKind.personal : LoanKind.consumer;
  var opening = LoanOpening.existing;
  String? account = accounts.firstOrNull;
  var category = 'other';
  var firstDue = addMonths(dateOnly(DateTime.now()), 1);

  int? rateBps() {
    final t = rate.text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    return v == null ? null : (v * 100).round();
  }

  Loan build() => Loan(
    name: nameC.text.trim(),
    lender: lender.text.trim().isEmpty ? null : lender.text.trim(),
    kind: kind,
    opening: opening,
    principalPaise: parseRupeesToPaise(principal.text) ?? 0,
    emiPaise: parseRupeesToPaise(emi.text) ?? 0,
    tenureMonths: int.tryParse(tenure.text) ?? 0,
    rateBps: rateBps(),
    startDate: firstDue,
    account: account,
  );

  final ok = await showFormSheet(
    context,
    title: const Text('Add loan or EMI'),
    submitLabel: 'Add loan',
    validate: () {
      if (nameC.text.trim().isEmpty) return 'Give the loan a name.';
      if (positiveAmountError(principal.text) != null) {
        return 'Enter the principal.';
      }
      if ((int.tryParse(tenure.text) ?? 0) <= 0) {
        return 'Enter the number of months.';
      }
      if (rate.text.trim().isNotEmpty && rateBps() == null) {
        return 'Enter the rate as a number, like 10.5.';
      }
      if (positiveAmountError(emi.text) != null) {
        return 'Enter the EMI (or tap Calculate).';
      }
      if (opening == LoanOpening.disbursed && account == null) {
        return 'Pick the account the money arrived in.';
      }
      final l = build();
      if (l.rateBps == null && l.emiPaise * l.tenureMonths < l.principalPaise) {
        return 'EMI × months is less than the principal.';
      }
      return null;
    },
    builder: (context, setState) {
      final text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final k in LoanKind.values)
                AppChoiceChip(
                  label: loanKindLabel(k),
                  selected: kind == k,
                  onTap: () => setState(() => kind = k),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: nameC,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Fridge, Car loan',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: lender,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Lender (optional)'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('How did it start?', style: text.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          SegmentedButton<LoanOpening>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LoanOpening.existing,
                label: Text('Already running'),
              ),
              ButtonSegment(
                value: LoanOpening.disbursed,
                label: Text('Money received'),
              ),
              ButtonSegment(
                value: LoanOpening.purchase,
                label: Text('Bought on EMI'),
              ),
            ],
            selected: {opening},
            onSelectionChanged: (s) => setState(() => opening = s.first),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(switch (opening) {
            LoanOpening.existing =>
              'No money moves now. Enter what is still owed and the EMIs left.',
            LoanOpening.disbursed =>
              'The loan amount is added to the account. It isn’t income.',
            LoanOpening.purchase => 'The item is recorded once as an expense today; EMIs then only repay the loan.',
          }, style: text.bodySmall),
          if (opening == LoanOpening.purchase) ...[
            const SizedBox(height: AppSpacing.md - 4),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Spending category'),
              items: [
                for (final c in {...kCategoryKeywords.keys, 'other'})
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (v) => setState(() => category = v ?? category),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: principal,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: opening == LoanOpening.existing
                  ? 'Principal still owed'
                  : 'Loan amount',
              prefixText: '$currency ',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tenure,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: opening == LoanOpening.existing
                        ? 'EMIs left'
                        : 'Months',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Rate % a year',
                    helperText: 'Optional',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: emi,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'EMI',
              prefixText: '$currency ',
              helperText: 'As the lender states it',
              suffixIcon: TextButton(
                onPressed: () {
                  final p = parseRupeesToPaise(principal.text);
                  final n = int.tryParse(tenure.text);
                  if (p == null || n == null || n <= 0) return;
                  setState(
                    () => emi.text = paiseToEditString(
                      emiFor(p, rateBps() ?? 0, n),
                    ),
                  );
                },
                child: const Text('Calculate'),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: firstDue,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
                helpText: 'Next EMI due on',
              );
              if (picked != null) setState(() => firstDue = picked);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text('Next EMI due ${shortDate(firstDue)}'),
          ),
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md - 4),
            _accountField(
              accounts,
              account,
              opening == LoanOpening.disbursed
                  ? 'Money arrived in'
                  : 'EMIs paid from',
              (v) => setState(() => account = v),
            ),
          ],
        ],
      );
    },
  );
  if (!ok || !context.mounted) return;
  try {
    await context.read<LoansController>().add(
      build(),
      purchaseCategory: category,
    );
    if (context.mounted) _snack(context, 'Loan added with its schedule.');
  } on LoanException catch (e) {
    if (context.mounted) _snack(context, e.message);
  }
}

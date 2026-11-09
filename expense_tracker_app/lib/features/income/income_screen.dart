import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/budgets.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/income_repository.dart';
import '../cycles/cycle_card.dart';
import '../cycles/cycle_controller.dart';
import '../expenses/expenses_controller.dart';
import '../settings/settings_controller.dart';
import 'income_controller.dart';

/// Income received (by source, for this month or this salary cycle) and
/// income still expected. Expected money is never added to what you have.
class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  bool _cycle = false;
  Map<IncomeSource, int> _bySource = {};
  late final ExpensesController _expenses;

  @override
  void initState() {
    super.initState();
    _expenses = context.read<ExpensesController>()..addListener(_load);
    _cycle =
        context.read<SettingsController>().config.periodView == 'cycle' &&
        context.read<CycleController>().hasCycles;
    _load();
  }

  @override
  void dispose() {
    _expenses.removeListener(_load);
    super.dispose();
  }

  PeriodRange get _range {
    final now = dateOnly(DateTime.now());
    final cycle = context.read<CycleController>().cycles.lastOrNull;
    if (_cycle && cycle != null) {
      return PeriodRange(cycle.start, cycle.queryEnd(now));
    }
    return PeriodRange(DateTime(now.year, now.month, 1), now);
  }

  Future<void> _load() async {
    final r = _range;
    final data = await context.read<IncomeController>().receivedBySource(
      r.start,
      r.end,
    );
    if (mounted) setState(() => _bySource = data);
  }

  Future<void> _addExpected() async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var source = IncomeSource.freelance;
    var date = dateOnly(DateTime.now()).add(const Duration(days: 7));
    final ok = await showFormSheet(
      context,
      title: const Text('Expected income'),
      subtitle:
          'Money you’re owed or due to get. It isn’t counted anywhere until '
          'you mark it received.',
      submitLabel: 'Add',
      validate: () => positiveAmountError(amount.text),
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final s in IncomeSource.values)
                AppChoiceChip(
                  label: incomeSourceLabel(s),
                  selected: source == s,
                  onTap: () => setState(() => source = s),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount expected'),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: date,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 2),
              );
              if (picked != null) setState(() => date = picked);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text('Expected on ${shortDate(date)}'),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: note,
            decoration: const InputDecoration(
              labelText: 'From / note (optional)',
            ),
          ),
        ],
      ),
    );
    if (!ok || !mounted) return;
    await context.read<IncomeController>().addExpected(
      ExpectedIncome(
        source: source,
        amountPaise: parseRupeesToPaise(amount.text)!,
        expectedDate: date,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      ),
    );
  }

  Future<void> _received(ExpectedIncome e, String currency) async {
    final amount = TextEditingController(
      text: paiseToEditString(e.amountPaise),
    );
    final ok = await showFormSheet(
      context,
      title: Text('${incomeSourceLabel(e.source)} received'),
      subtitle:
          'Enter what actually arrived. It’s recorded as income today and '
          'counts from now on.',
      submitLabel: 'Record income',
      validate: () => positiveAmountError(amount.text),
      builder: (context, setState) => TextField(
        controller: amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: 'Amount received',
          prefixText: '$currency ',
        ),
      ),
    );
    if (!ok || !mounted) return;
    await context.read<IncomeController>().markReceived(
      e,
      amountPaise: parseRupeesToPaise(amount.text)!,
      date: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final income = context.watch<IncomeController>();
    final hasCycles = context.select<CycleController, bool>((c) => c.hasCycles);
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final total = _bySource.values.fold<int>(0, (s, v) => s + v);
    final rows = _bySource.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final pending = income.pending;
    final today = dateOnly(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'expected_income',
        onPressed: _addExpected,
        icon: const Icon(Icons.schedule_rounded),
        label: const Text('Expected income'),
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
            if (hasCycles) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('This month')),
                  ButtonSegment(value: true, label: Text('This cycle')),
                ],
                selected: {_cycle},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _cycle = s.first);
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Received', style: text.labelMedium),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    formatMoney(total, currency),
                    style: text.moneyStyle(26, color: p.income),
                  ),
                  if (income.pendingTotal > 0)
                    Text(
                      '+ ${formatMoney(income.pendingTotal, currency)} expected '
                      '(not counted)',
                      style: text.bodySmall,
                    ),
                  if (rows.isNotEmpty) const SizedBox(height: AppSpacing.md),
                  for (final e in rows)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  incomeSourceLabel(e.key),
                                  style: text.bodyMedium,
                                ),
                              ),
                              Text(
                                formatMoney(e.value, currency),
                                style: text.moneyStyle(14),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: LinearProgressIndicator(
                              value: total > 0 ? e.value / total : 0,
                              minHeight: AppSizes.progressBar - 2,
                              color: p.income,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'No income recorded in this period yet.',
                        style: text.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Expected'),
            if (pending.isEmpty)
              AppCard(
                child: Text(
                  'Nothing expected. Add money you’re owed — a freelance '
                  'invoice, a bonus, a reimbursement — to see it here without '
                  'it inflating your balance.',
                  style: text.bodyMedium,
                ),
              ),
            for (final e in pending)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.note ?? incomeSourceLabel(e.source),
                              style: text.titleSmall,
                            ),
                            Text(
                              '${incomeSourceLabel(e.source)} · '
                              '${e.expectedDate.isBefore(today) ? 'was due' : 'due'} '
                              '${shortDate(e.expectedDate)}',
                              style: text.bodySmall?.copyWith(
                                color: e.expectedDate.isBefore(today)
                                    ? p.warning
                                    : null,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxs),
                            Text(
                              formatMoney(e.amountPaise, currency),
                              style: text.moneyStyle(16),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          FilledButton(
                            onPressed: () => _received(e, currency),
                            child: const Text('Received'),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.read<IncomeController>().cancel(e),
                            child: const Text('Not coming'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

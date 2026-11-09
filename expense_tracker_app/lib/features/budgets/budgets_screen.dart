import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/categories.dart';
import '../../core/finance/budgets.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/category_icon.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../data/repositories/budget_repository.dart';
import '../cycles/cycle_card.dart';
import '../cycles/cycle_controller.dart';
import '../settings/settings_controller.dart';
import 'budget_controller.dart';

Color levelColor(BudgetLevel l, AppPalette p) => switch (l) {
  BudgetLevel.ok => p.savings,
  BudgetLevel.caution => p.warning,
  BudgetLevel.reached || BudgetLevel.exceeded => p.expense,
};

String levelLabel(BudgetLevel l) => switch (l) {
  BudgetLevel.ok => 'On track',
  BudgetLevel.caution => 'Near limit',
  BudgetLevel.reached => 'Limit reached',
  BudgetLevel.exceeded => 'Over budget',
};

class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});

  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  BudgetPeriod? _filter;

  @override
  Widget build(BuildContext context) {
    final budgets = context.watch<BudgetController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final cycleIncome = context.select<CycleController, int?>(
      (c) => c.current?.income.total,
    );
    final usages = budgets.usages
        .where((u) => _filter == null || u.budget.period == _filter)
        .toList();
    // Budgets with no current period (a cycle budget before any cycle).
    final waiting = budgets.budgets
        .where(
          (b) =>
              (_filter == null || b.period == _filter) &&
              !budgets.usages.any((u) => u.budget.id == b.id),
        )
        .toList();
    final cycleBudgets = budgets.budgets.where(
      (b) => b.period == BudgetPeriod.cycle,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_budget',
        onPressed: () => showBudgetForm(context, period: _filter),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add budget'),
      ),
      body: ResponsivePage(
        builder: (context, gutter) => ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.navClearance),
          children: [
            ChipRow(
              children: [
                AppChoiceChip(
                  label: 'All',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                ),
                for (final p in BudgetPeriod.values)
                  AppChoiceChip(
                    label: budgetPeriodLabel(p),
                    selected: _filter == p,
                    onTap: () => setState(() => _filter = p),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (cycleIncome != null &&
                      cycleBudgets.isNotEmpty &&
                      (_filter == null || _filter == BudgetPeriod.cycle))
                    _CycleIncomeNote(
                      gap: cycleBudgetGap(cycleIncome, cycleBudgets),
                      income: cycleIncome,
                      currency: currency,
                    ),
                  if (usages.isEmpty && waiting.isEmpty)
                    AppCard(
                      child: EmptyState(
                        icon: Icons.pie_chart_outline_rounded,
                        title: 'No budgets here yet',
                        message:
                            'Set a limit for a salary cycle, a month, a week, '
                            'a day or your own dates — for all spending or one '
                            'category.',
                        action: 'Add budget',
                        onAction: () =>
                            showBudgetForm(context, period: _filter),
                      ),
                    ),
                  for (final u in usages)
                    _BudgetCard(usage: u, currency: currency),
                  for (final b in waiting)
                    _WaitingCard(budget: b, currency: currency),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CycleIncomeNote extends StatelessWidget {
  final int gap;
  final int income;
  final String currency;
  const _CycleIncomeNote({
    required this.gap,
    required this.income,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final over = gap < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Row(
          children: [
            Icon(
              over ? Icons.warning_amber_rounded : Icons.payments_outlined,
              color: over ? p.warning : p.income,
            ),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Text(
                over
                    ? 'Cycle budgets promise ${formatMoney(-gap, currency)} more '
                          'than the ${formatMoney(income, currency)} received '
                          'this cycle.'
                    : '${formatMoney(gap, currency)} of this cycle’s '
                          '${formatMoney(income, currency)} income has no '
                          'budget yet.',
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  final BudgetUsage usage;
  final String currency;
  const _BudgetCard({required this.usage, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final b = usage.budget;
    final color = levelColor(usage.level, p);
    final range = usage.range;
    final period = b.period == BudgetPeriod.day
        ? 'Today'
        : '${budgetPeriodLabel(b.period)} · ${shortDate(range.start)} – '
              '${shortDate(range.end)}';
    final perDay = usage.perDayLeft;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => showBudgetForm(context, existing: b),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                b.category == null
                    ? CategoryIcon(
                        category: 'all',
                        icon: Icons.account_balance_wallet_rounded,
                        color: p.savings,
                        size: 36,
                      )
                    : CategoryIcon(category: b.category!, size: 36),
                const SizedBox(width: AppSpacing.md - 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              b.label,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                          ),
                          if (b.essential) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.verified_rounded,
                              size: AppIconSize.sm,
                              color: p.savings,
                              semanticLabel: 'Essential',
                            ),
                          ],
                        ],
                      ),
                      Text(period, style: text.bodySmall),
                    ],
                  ),
                ),
                Text(
                  '${usage.percent}%',
                  style: text.titleSmall?.copyWith(color: color),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            BudgetProgressBar(
              spent: usage.spent.clamp(0, usage.limit * 2),
              budget: usage.limit,
              color: color,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${formatMoney(usage.spent, currency)} of '
                    '${formatMoney(usage.limit, currency)}',
                    style: text.bodySmall,
                  ),
                ),
                Text(
                  usage.remaining >= 0
                      ? '${formatMoney(usage.remaining, currency)} left'
                      : '${formatMoney(-usage.remaining, currency)} over',
                  style: text.labelMedium?.copyWith(
                    color: usage.remaining >= 0 ? p.textPrimary : p.expense,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              [
                levelLabel(usage.level),
                if (perDay != null && b.period != BudgetPeriod.day)
                  '${formatMoney(perDay, currency)}/day for '
                      '${usage.daysLeft} day${usage.daysLeft == 1 ? '' : 's'}',
              ].join(' · '),
              style: text.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaitingCard extends StatelessWidget {
  final Budget budget;
  final String currency;
  const _WaitingCard({required this.budget, required this.currency});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => showBudgetForm(context, existing: budget),
        child: Row(
          children: [
            const Icon(Icons.hourglass_empty_rounded),
            const SizedBox(width: AppSpacing.md - 4),
            Expanded(
              child: Text(
                '${budget.label} · ${budgetPeriodLabel(budget.period)} · '
                '${formatMoney(budget.limitPaise, currency)}\n'
                'Starts with your first salary cycle.',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or edit a budget. Limits are only ever changed here — never
/// automatically when income changes.
Future<void> showBudgetForm(
  BuildContext context, {
  Budget? existing,
  BudgetPeriod? period,
}) async {
  final controller = context.read<BudgetController>();
  final custom = context.read<SettingsController>().config.customCategories;
  final categories = {...kCategoryKeywords.keys, ...custom.keys}.toList()
    ..sort();
  final limit = TextEditingController(
    text: existing == null ? '' : paiseToEditString(existing.limitPaise),
  );
  var p = existing?.period ?? period ?? BudgetPeriod.month;
  String? category = existing?.category;
  var caution = existing?.cautionPct ?? 80;
  var essential = existing?.essential ?? false;
  var essentialTouched = existing != null;
  DateTime? start = existing?.start;
  DateTime? end = existing?.end;

  Budget build() => Budget(
    id: existing?.id,
    period: p,
    category: category,
    limitPaise: parseRupeesToPaise(limit.text) ?? 0,
    start: p == BudgetPeriod.custom ? start : null,
    end: p == BudgetPeriod.custom ? end : null,
    cautionPct: caution,
    essential: essential,
  );

  final ok = await showFormSheet(
    context,
    title: Text(existing == null ? 'Add budget' : 'Edit budget'),
    subtitle: 'Counts spending net of refunds in the period.',
    submitLabel: existing == null ? 'Add budget' : 'Save',
    validate: () => validateBudget(build(), controller.budgets),
    builder: (context, setState) {
      final text = Theme.of(context).textTheme;
      Future<void> pickDate(bool isStart) async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: (isStart ? start : end) ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 2),
        );
        if (picked != null) {
          setState(() => isStart ? start = picked : end = picked);
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<BudgetPeriod>(
              segments: [
                for (final v in BudgetPeriod.values)
                  ButtonSegment(value: v, label: Text(budgetPeriodLabel(v))),
              ],
              selected: {p},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => p = s.first),
            ),
          ),
          if (p == BudgetPeriod.cycle)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Runs from your salary date until the next salary is '
                'expected.',
                style: text.bodySmall,
              ),
            ),
          if (p == BudgetPeriod.custom) ...[
            const SizedBox(height: AppSpacing.md - 4),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pickDate(true),
                    child: Text(
                      start == null ? 'Start date' : shortDate(start!),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pickDate(false),
                    child: Text(end == null ? 'End date' : shortDate(end!)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md - 4),
          DropdownButtonFormField<String?>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Applies to'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All spending')),
              for (final c in categories)
                DropdownMenuItem(
                  value: c,
                  child: Text('${c[0].toUpperCase()}${c.substring(1)}'),
                ),
            ],
            onChanged: (v) => setState(() {
              category = v;
              // Rent, bills, groceries, health and transport default to
              // essential until the user decides.
              if (!essentialTouched) {
                essential = kRecommendedAllocation[v]?.$1 == 'needs';
              }
            }),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: limit,
            autofocus: existing == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Limit'),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Warn me at $caution% used', style: text.titleSmall),
          Slider(
            value: caution.toDouble(),
            min: 50,
            max: 95,
            divisions: 9,
            label: '$caution%',
            onChanged: (v) => setState(() => caution = v.round()),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Essential'),
            subtitle: const Text(
              'Needs like rent and groceries. Money allocation funds these '
              'first.',
            ),
            value: essential,
            onChanged: (v) => setState(() {
              essential = v;
              essentialTouched = true;
            }),
          ),
          if (existing != null)
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await controller.remove(existing.id!);
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Delete this budget'),
            ),
        ],
      );
    },
  );
  if (!ok || !context.mounted) return;
  try {
    await controller.save(build());
  } on BudgetException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

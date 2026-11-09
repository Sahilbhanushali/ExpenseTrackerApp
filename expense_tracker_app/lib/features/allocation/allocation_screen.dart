import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/allocation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../data/repositories/allocation_repository.dart';
import '../cycles/cycle_card.dart';
import 'allocation_controller.dart';

void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

Future<void> _guard(
  BuildContext context,
  Future<void> Function() f, [
  String? done,
]) async {
  try {
    await f();
    if (done != null && context.mounted) _snack(context, done);
  } on AllocationException catch (e) {
    if (context.mounted) _snack(context, e.message);
  } on StateError catch (e) {
    if (context.mounted) _snack(context, e.message);
  }
}

class AllocationScreen extends StatefulWidget {
  const AllocationScreen({super.key});

  @override
  State<AllocationScreen> createState() => _AllocationScreenState();
}

class _AllocationScreenState extends State<AllocationScreen> {
  @override
  void initState() {
    super.initState();
    context.read<AllocationController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AllocationController>();
    final v = controller.view;
    final text = Theme.of(context).textTheme;
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart allocation'),
        actions: [
          IconButton(
            tooltip: 'Allocation settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: v == null
          ? const Padding(
              padding: EdgeInsets.all(AppSpacing.page),
              child: SkeletonList(),
            )
          : ResponsivePage(
              builder: (context, gutter) {
                final cur = v.snapshot.currency;
                String fmt(int x) => formatMoney(x, cur);
                final plan = v.plan;
                final byBucket = <AllocBucket, List<AllocationLine>>{};
                for (final l in plan.lines) {
                  (byBucket[l.need.bucket] ??= []).add(l);
                }
                final order = [
                  ...controller.config.order,
                  ...AllocBucket.values.where(
                    (b) =>
                        b != AllocBucket.buffer &&
                        !controller.config.order.contains(b),
                  ),
                ];
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppSpacing.sm,
                    gutter,
                    AppSpacing.xl,
                  ),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Available to allocate',
                            style: text.labelMedium,
                          ),
                          Text(
                            fmt(plan.available),
                            style: text.moneyStyle(
                              28,
                              color: plan.available < 0 ? p.expense : null,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'In spendable accounts ${fmt(v.snapshot.liquid)} · '
                            'already reserved ${fmt(v.reserved)}',
                            style: text.bodySmall,
                          ),
                          Text(
                            'Planning until ${shortDate(v.snapshot.horizon)} — when your '
                            'next salary is expected at the latest. Savings, emergency '
                            'and investment accounts aren’t counted as spendable.',
                            style: text.bodySmall,
                          ),
                          if (plan.proposedTotal > 0) ...[
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.icon(
                              onPressed: () => _guard(context, () async {
                                final n = await controller.approveAll();
                                if (context.mounted) {
                                  _snack(context, 'Approved $n allocations.');
                                }
                              }),
                              icon: const Icon(Icons.done_all_rounded),
                              label: Text(
                                'Approve all · ${fmt(plan.proposedTotal)}',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Approving sets money aside. Nothing moves at the bank — '
                              'transfers wait until you mark them done.',
                              style: text.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (plan.criticalShortfall > 0) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ShortfallCard(view: v),
                    ],
                    if (plan.lines.isEmpty && v.skipped.isEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      AppCard(
                        child: EmptyState(
                          icon: Icons.account_tree_outlined,
                          title: 'Nothing to plan yet',
                          message:
                              'Allocation works from your real numbers: budgets '
                              '(mark needs as essential), card statements, loans, '
                              'recurring bills, and the savings, emergency and '
                              'investing amounts in settings.',
                          action: 'Open settings',
                          onAction: () => _showSettings(context),
                        ),
                      ),
                    ],
                    for (final b in order)
                      if (byBucket[b] case final lines?) ...[
                        const SizedBox(height: AppSpacing.lg),
                        SectionHeader(
                          '${order.indexOf(b) + 1}. ${bucketLabel(b)}',
                        ),
                        for (final l in lines) _LineCard(line: l, view: v),
                      ],
                    if (plan.lines.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppCard(
                        child: Row(
                          children: [
                            Icon(Icons.savings_outlined, color: p.savings),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                plan.buffer > 0
                                    ? '${fmt(plan.buffer)} left as a buffer. It stays '
                                          'available for surprises.'
                                    : 'No buffer left after these.',
                                style: text.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (v.skipped.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const SectionHeader('Skipped this period'),
                      for (final n in v.skipped)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: AppCard(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(n.label, style: text.bodyMedium),
                                ),
                                TextButton(
                                  onPressed: () => _guard(
                                    context,
                                    () => controller.release(
                                      v.decisionFor(n.key)!,
                                    ),
                                  ),
                                  child: const Text('Undo'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _ShortfallCard extends StatelessWidget {
  final AllocationView view;
  const _ShortfallCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final cur = view.snapshot.currency;
    final unmet = view.plan.unmet.take(4).toList();
    final adjustable = view.plan.lines
        .where((l) => l.need.bucket == AllocBucket.discretionary)
        .map((l) => l.need.label)
        .take(3)
        .toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: p.expense),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${formatMoney(view.plan.criticalShortfall, cur)} short for '
                  'what’s due before ${shortDate(view.snapshot.horizon)}',
                  style: text.titleSmall?.copyWith(color: p.expense),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final l in unmet)
            Text(
              '• ${l.need.label}: ${formatMoney(l.shortfall, cur)} not covered'
              '${l.need.dueDate == null ? '' : ' (due ${shortDate(l.need.dueDate!)})'}',
              style: text.bodySmall,
            ),
          if (adjustable.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Budgets that may need trimming: ${adjustable.join(', ')}.',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The plan isn’t forced to balance — this gap is real until more '
            'money comes in or something is reduced.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final AllocationLine line;
  final AllocationView view;
  const _LineCard({required this.line, required this.view});

  Future<void> _edit(BuildContext context) async {
    final controller = context.read<AllocationController>();
    final cur = view.snapshot.currency;
    final amount = TextEditingController(
      text: paiseToEditString(line.proposed),
    );
    final names = controller.destinations();
    String? dest = names.contains(line.need.destination)
        ? line.need.destination
        : names.firstOrNull;
    final max = line.proposed + view.plan.buffer;
    final ok = await showFormSheet(
      context,
      title: Text(line.need.label),
      subtitle: line.need.reason,
      submitLabel: 'Approve',
      validate: () {
        final e = positiveAmountError(amount.text);
        if (e != null) return e;
        return parseRupeesToPaise(amount.text)! > max
            ? 'Only ${formatMoney(max, cur)} is unallocated.'
            : null;
      },
      builder: (context, setState) {
        final pay = parseRupeesToPaise(amount.text) ?? 0;
        final move = controller.moveFor(line, pay + line.reserved, dest);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: amount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$cur ',
              ),
            ),
            const SizedBox(height: AppSpacing.md - 4),
            if (names.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: dest,
                decoration: const InputDecoration(labelText: 'Keep it in'),
                items: [
                  for (final n in names)
                    DropdownMenuItem(value: n, child: Text(n)),
                ],
                onChanged: (v) => setState(() => dest = v),
              ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              move.from == null
                  ? 'No transfer needed — the money is already there.'
                  : 'A planned transfer of ${formatMoney(move.transfer, cur)} '
                        'from ${move.from} will wait until you mark it done.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
    if (!ok || !context.mounted) return;
    await _guard(
      context,
      () => controller.approve(
        line,
        amount: parseRupeesToPaise(amount.text),
        destination: dest,
      ),
      'Reserved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<AllocationController>();
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final cur = view.snapshot.currency;
    String fmt(int x) => formatMoney(x, cur);
    final n = line.need;
    final d = view.decisionFor(n.key);
    final move = controller.moveFor(
      line,
      line.proposed + line.reserved,
      n.destination,
    );
    final where = n.destination == null
        ? 'No account with this role yet'
        : move.from == null
        ? 'Keep in ${n.destination}'
        : 'Move ${fmt(move.transfer)} to ${n.destination} from ${move.from}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.label, style: text.titleSmall),
                      if (n.dueDate != null)
                        Text(
                          'Due ${shortDate(n.dueDate!)}',
                          style: text.bodySmall?.copyWith(
                            color: n.revolving ? p.expense : null,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmt(line.proposed + line.reserved),
                      style: text.moneyStyle(16),
                    ),
                    Text('of ${fmt(n.required)}', style: text.labelSmall),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(n.reason, style: text.bodySmall),
            if (line.skippedBecause != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Not funded: ${line.skippedBecause}',
                  style: text.bodySmall?.copyWith(color: p.warning),
                ),
              ),
            if (line.shortfall > 0)
              Text(
                '${fmt(line.shortfall)} short',
                style: text.labelMedium?.copyWith(color: p.expense),
              ),
            const SizedBox(height: AppSpacing.xs),
            Text(where, style: text.labelSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (d?.status == DecisionStatus.reserved) ...[
                  _Pill(label: 'Reserved ${fmt(d!.amount)}', color: p.income),
                  if (d.movementId != null)
                    FilledButton(
                      onPressed: () => _guard(
                        context,
                        () => controller.markTransferred(d),
                        'Transfer done. Balances updated.',
                      ),
                      child: const Text('Transfer done'),
                    ),
                  TextButton(
                    onPressed: () => _guard(
                      context,
                      () => controller.release(d),
                      'Released.',
                    ),
                    child: const Text('Release'),
                  ),
                ],
                if (d?.status == DecisionStatus.transferred)
                  _Pill(label: 'Moved ${fmt(d!.amount)}', color: p.income),
                if (line.proposed > 0) ...[
                  FilledButton(
                    onPressed: () => _guard(
                      context,
                      () => controller.approve(line),
                      'Reserved.',
                    ),
                    child: Text(d == null ? 'Approve' : 'Top up'),
                  ),
                  OutlinedButton(
                    onPressed: () => _edit(context),
                    child: const Text('Edit'),
                  ),
                ],
                if (d == null && line.skippedBecause == null)
                  TextButton(
                    onPressed: () => _guard(context, () => controller.skip(n)),
                    child: const Text('Skip'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.sm,
      vertical: AppSpacing.xxs + 1,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_rounded, size: AppIconSize.sm, color: color),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: color),
        ),
      ],
    ),
  );
}

Future<void> _showSettings(BuildContext context) async {
  final controller = context.read<AllocationController>();
  final cur = controller.view?.snapshot.currency ?? '₹';
  final c = controller.config;
  final order = [...c.order];
  TextEditingController money(int? v) =>
      TextEditingController(text: v == null ? '' : paiseToEditString(v));
  final target = money(c.emergencyTarget);
  final monthly = money(c.emergencyMonthly);
  final savings = money(c.savingsPerCycle);
  final invest = money(c.investPerCycle);
  int? read(TextEditingController t) =>
      t.text.trim().isEmpty ? null : parseRupeesToPaise(t.text);

  final ok = await showFormSheet(
    context,
    title: const Text('Allocation settings'),
    subtitle: 'Higher in the list is funded first.',
    submitLabel: 'Save',
    validate: () =>
        [target, monthly, savings, invest].any(
          (t) => t.text.trim().isNotEmpty && parseRupeesToPaise(t.text) == null,
        )
        ? 'One of the amounts isn’t a number.'
        : null,
    builder: (context, setState) {
      final text = Theme.of(context).textTheme;
      Widget field(TextEditingController t, String label, String helper) =>
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TextField(
              controller: t,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: label,
                helperText: helper,
                prefixText: '$cur ',
              ),
            ),
          );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, b) in order.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Text('${i + 1}', style: text.titleSmall),
              title: Text(bucketLabel(b)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: i == 0
                        ? null
                        : () => setState(
                            () => order.insert(i - 1, order.removeAt(i)),
                          ),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    onPressed: i == order.length - 1
                        ? null
                        : () => setState(
                            () => order.insert(i + 1, order.removeAt(i)),
                          ),
                    icon: const Icon(Icons.arrow_downward_rounded),
                  ),
                ],
              ),
            ),
          Text(
            'Overdue card debt is always funded before savings, investing and '
            'discretionary spending.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          field(target, 'Emergency fund target', 'Total you want set aside'),
          field(
            monthly,
            'Emergency contribution',
            'Per period, until the target',
          ),
          field(savings, 'Short-term savings', 'Per period'),
          field(
            invest,
            'Investing',
            'Per period — skipped while dues are at risk',
          ),
        ],
      );
    },
  );
  if (!ok || !context.mounted) return;
  await _guard(
    context,
    () => controller.saveSettings(
      AllocationSettings(
        order: order,
        emergencyTarget: read(target),
        emergencyMonthly: read(monthly),
        savingsPerCycle: read(savings),
        investPerCycle: read(invest),
      ),
    ),
    'Saved.',
  );
}

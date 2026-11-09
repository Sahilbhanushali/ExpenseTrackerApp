import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/wealth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../data/models/account.dart';
import '../../data/models/goal.dart';
import '../../data/repositories/goal_repository.dart';
import '../accounts/accounts_controller.dart';
import '../cycles/cycle_card.dart';
import '../settings/settings_controller.dart';
import 'goals_controller.dart';

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
  } on GoalException catch (e) {
    if (context.mounted) _snack(context, e.message);
  }
}

const _priorities = {1: 'High', 2: 'Medium', 3: 'Low'};

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final goals = context.watch<GoalsController>();
    final accounts = context.watch<AccountsController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final earmarked = goals.earmarked();
    final over = [
      for (final e in earmarked.entries)
        if (e.value >
            (accounts.accounts
                    .where((a) => a.account.name == e.key)
                    .firstOrNull
                    ?.balance ??
                0))
          e.key,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_goal',
        onPressed: () => showGoalForm(context),
        icon: const Icon(Icons.flag_rounded),
        label: const Text('Add goal'),
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
            Text(
              'A goal is a label on money in a savings account — it’s counted '
              'once, in that account. Adding to a goal is a transfer, never '
              'spending.',
              style: text.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final a in over)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: AppCard(
                  child: Text(
                    'Goals in $a claim more than the account holds. Check its '
                    'balance or what was taken out.',
                    style: text.bodyMedium?.copyWith(color: p.warning),
                  ),
                ),
              ),
            if (goals.goals.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'No goals yet',
                  message:
                      'A new laptop, a trip, a vehicle, long-term wealth — set a '
                      'target and a date, link a savings account, and see what '
                      'each month needs.',
                  action: 'Add goal',
                  onAction: () => showGoalForm(context),
                ),
              ),
            for (final g in goals.goals)
              _GoalCard(standing: g, currency: currency),
          ],
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalStanding standing;
  final String currency;
  const _GoalCard({required this.standing, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final g = standing.goal;
    final pr = standing.progress;
    final today = DateTime.now();
    final need = pr.requiredMonthly(today);
    final onTrack = pr.onTrack(today);
    String fmt(int v) => formatMoney(v, currency);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () => _actions(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  g.achieved ? Icons.emoji_events_rounded : Icons.flag_rounded,
                  color: g.achieved ? p.income : p.savings,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: text.titleSmall),
                      Text(
                        [
                          '${_priorities[g.priority]} priority',
                          g.horizon == GoalHorizon.long
                              ? 'long-term'
                              : 'short-term',
                          if (g.account != null) 'in ${g.account}',
                        ].join(' · '),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text('${pr.percent}%', style: text.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            BudgetProgressBar(
              spent: standing.saved.clamp(0, g.targetPaise),
              budget: g.targetPaise,
              color: p.income,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${fmt(standing.saved)} of ${fmt(g.targetPaise)} · ${fmt(pr.remaining)} to go',
              style: text.bodySmall,
            ),
            if (g.targetDate != null && !pr.reached)
              Text(
                [
                  'By ${shortDate(g.targetDate!)}',
                  if (need != null) 'needs ${fmt(need)}/month',
                  if (onTrack == true) 'on track',
                  if (onTrack == false)
                    'behind — plan ${fmt(g.monthlyContributionPaise!)}/month',
                ].join(' · '),
                style: text.labelMedium?.copyWith(
                  color: onTrack == false
                      ? p.warning
                      : onTrack == true
                      ? p.income
                      : null,
                ),
              ),
            if (g.account == null)
              Text(
                'Link a savings account to add money.',
                style: text.labelMedium?.copyWith(color: p.warning),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context) async {
    final g = standing;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!g.goal.achieved && g.goal.account != null)
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Add money'),
                subtitle: Text('Transfer into ${g.goal.account}'),
                onTap: () => Navigator.pop(sheet, 'add'),
              ),
            if (g.saved > 0 && g.goal.account != null)
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('Take money out'),
                subtitle: Text('Transfer from ${g.goal.account}'),
                onTap: () => Navigator.pop(sheet, 'out'),
              ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit goal'),
              onTap: () => Navigator.pop(sheet, 'edit'),
            ),
            ListTile(
              leading: Icon(
                g.goal.achieved
                    ? Icons.replay_rounded
                    : Icons.emoji_events_outlined,
              ),
              title: Text(
                g.goal.achieved ? 'Mark as active again' : 'Mark as achieved',
              ),
              onTap: () => Navigator.pop(sheet, 'achieved'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete goal'),
              subtitle: const Text('The money stays in its account'),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final controller = context.read<GoalsController>();
    switch (action) {
      case 'add':
      case 'out':
        await _move(context, action == 'add');
      case 'edit':
        await showGoalForm(context, existing: g.goal, saved: g.saved);
      case 'achieved':
        await _guard(
          context,
          () => controller.setAchieved(g, !g.goal.achieved),
        );
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Delete “${g.goal.name}”?'),
            content: const Text(
              'Only the goal is removed; the money stays where it is.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok == true && context.mounted) {
          await _guard(context, () => controller.remove(g));
        }
    }
  }

  Future<void> _move(BuildContext context, bool adding) async {
    final g = standing;
    final names = [
      for (final a in context.read<AccountsController>().active)
        if (a.account.name != g.goal.account &&
            (!adding ||
                a.account.isSpendable ||
                a.account.roles.contains(AccountRole.salary)))
          a.account.name,
    ];
    if (names.isEmpty) return _snack(context, 'Add a spending account first.');
    String? other = names.first;
    var done = true;
    final amount = TextEditingController(
      text: adding
          ? switch (g.progress.suggested(DateTime.now())) {
              final v? => paiseToEditString(v),
              null => '',
            }
          : '',
    );
    final ok = await showFormSheet(
      context,
      title: Text(
        adding ? 'Add to ${g.goal.name}' : 'Take out of ${g.goal.name}',
      ),
      subtitle: adding
          ? 'A transfer into ${g.goal.account}. Saving isn’t spending.'
          : '${formatMoney(g.saved, currency)} saved. Moves back to an account you spend from.',
      submitLabel: adding ? 'Add money' : 'Take out',
      validate: () {
        final e = positiveAmountError(amount.text);
        if (e != null) return e;
        if (!adding && parseRupeesToPaise(amount.text)! > g.saved) {
          return 'That’s more than is saved for it.';
        }
        return null;
      },
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: amount,
            autofocus: amount.text.isEmpty,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '$currency ',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          DropdownButtonFormField<String>(
            initialValue: other,
            decoration: InputDecoration(labelText: adding ? 'From' : 'To'),
            items: [
              for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (v) => setState(() => other = v),
          ),
          if (adding)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: done,
              onChanged: (v) => setState(() => done = v),
              title: const Text('Already done at the bank'),
              subtitle: Text(
                done ? 'Counts now.' : 'Saved as planned; counts once done.',
              ),
            ),
        ],
      ),
    );
    if (!ok || !context.mounted) return;
    final paise = parseRupeesToPaise(amount.text)!;
    final controller = context.read<GoalsController>();
    await _guard(
      context,
      () => adding
          ? controller.contribute(
              g,
              from: other!,
              amountPaise: paise,
              done: done,
            )
          : controller.withdraw(g, to: other!, amountPaise: paise),
      adding ? 'Added.' : 'Taken out.',
    );
  }
}

Future<void> showGoalForm(
  BuildContext context, {
  Goal? existing,
  int saved = 0,
}) async {
  final controller = context.read<GoalsController>();
  final currency = context.read<SettingsController>().config.currency;
  final accounts = context.read<AccountsController>().active;
  final preferred = [
    for (final a in accounts)
      if (a.account.roles.contains(AccountRole.savings) ||
          a.account.roles.contains(AccountRole.investment) ||
          !a.account.isSpendable)
        a.account.name,
  ];
  final names = {
    ...preferred,
    for (final a in accounts) a.account.name,
  }.toList();
  final name = TextEditingController(text: existing?.name ?? '');
  TextEditingController money(int? v) => TextEditingController(
    text: v == null || v == 0 ? '' : paiseToEditString(v),
  );
  final target = money(existing?.targetPaise);
  final starting = money(existing?.startingPaise);
  final monthly = money(existing?.monthlyContributionPaise);
  var date = existing?.targetDate;
  var priority = existing?.priority ?? 2;
  var horizon = existing?.horizon ?? GoalHorizon.short;
  String? account = names.contains(existing?.account)
      ? existing?.account
      : preferred.firstOrNull;

  Goal build() => Goal(
    id: existing?.id,
    name: name.text.trim(),
    targetPaise: parseRupeesToPaise(target.text) ?? 0,
    startingPaise: starting.text.trim().isEmpty
        ? 0
        : parseRupeesToPaise(starting.text) ?? -1,
    monthlyContributionPaise: monthly.text.trim().isEmpty
        ? null
        : parseRupeesToPaise(monthly.text),
    targetDate: date,
    priority: priority,
    horizon: horizon,
    account: account,
    note: existing?.note,
    achieved: existing?.achieved ?? false,
    createdAt: existing?.createdAt ?? DateTime.now().toIso8601String(),
  );

  final ok = await showFormSheet(
    context,
    title: Text(existing == null ? 'Add goal' : 'Edit goal'),
    submitLabel: existing == null ? 'Add goal' : 'Save',
    validate: () {
      if (name.text.trim().isEmpty) return 'Give the goal a name.';
      if (positiveAmountError(target.text) != null) {
        return 'Enter the target amount.';
      }
      if (starting.text.trim().isNotEmpty &&
          parseRupeesToPaise(starting.text) == null) {
        return 'Enter what’s already saved as a number.';
      }
      if (monthly.text.trim().isNotEmpty &&
          parseRupeesToPaise(monthly.text) == null) {
        return 'Enter the monthly amount as a number.';
      }
      return null;
    },
    builder: (context, setState) {
      final text = Theme.of(context).textTheme;
      final g = build();
      final need = GoalProgress(
        target: g.targetPaise,
        saved:
            g.startingPaise +
            (existing == null ? 0 : saved - existing.startingPaise),
        targetDate: date,
      ).requiredMonthly(DateTime.now());
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Goal',
              hintText: 'e.g. New laptop',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: target,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Target amount'),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: starting,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Already saved for it',
              helperText: 'Money already in the linked account for this',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: date ?? DateTime(now.year + 1, now.month, 1),
                firstDate: now,
                lastDate: DateTime(now.year + 40),
                helpText: 'Reach it by',
              );
              if (d != null) setState(() => date = d);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text(
              date == null
                  ? 'Target date (optional)'
                  : 'By ${shortDate(date!)} ${date!.year}',
            ),
          ),
          if (need != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Needs about ${formatMoney(need, currency)} a month.',
                style: text.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: monthly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Planned per month (optional)',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Priority', style: text.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final e in _priorities.entries)
                AppChoiceChip(
                  label: e.value,
                  selected: priority == e.key,
                  onTap: () => setState(() => priority = e.key),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<GoalHorizon>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: GoalHorizon.short,
                label: Text('Short-term'),
              ),
              ButtonSegment(
                value: GoalHorizon.long,
                label: Text('Long-term wealth'),
              ),
            ],
            selected: {horizon},
            onSelectionChanged: (s) => setState(() => horizon = s.first),
          ),
          if (names.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md - 4),
            DropdownButtonFormField<String>(
              initialValue: account,
              decoration: const InputDecoration(
                labelText: 'Money is kept in',
                helperText: 'Usually a savings or investment account',
              ),
              items: [
                for (final n in names)
                  DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) => setState(() => account = v),
            ),
          ],
        ],
      );
    },
  );
  if (!ok || !context.mounted) return;
  await _guard(
    context,
    () => controller.save(build()),
    existing == null ? 'Goal added.' : 'Saved.',
  );
}

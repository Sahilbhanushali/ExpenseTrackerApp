import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/wealth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../accounts/account_detail_screen.dart';
import '../cycles/cycle_card.dart';
import '../settings/settings_controller.dart';
import 'emergency_controller.dart';

String _sourceLabel(EssentialSource s) => switch (s) {
  EssentialSource.override => 'the amount you entered',
  EssentialSource.budgets => 'your essential budgets',
  EssentialSource.spending => 'your spending on needs over the last 3 months',
  EssentialSource.none => 'nothing yet',
};

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  List<(String, String, int)> _withdrawals = [];

  @override
  void initState() {
    super.initState();
    final c = context.read<EmergencyController>();
    c.refresh().then((_) async {
      final w = await c.withdrawals();
      if (mounted) setState(() => _withdrawals = w);
    });
  }

  Future<void> _editTarget(BuildContext context) async {
    final c = context.read<EmergencyController>();
    final cur = context.read<SettingsController>().config.currency;
    final cfg = c.config;
    int? months =
        cfg.emergencyMonths ?? (cfg.emergencyTarget == null ? 6 : null);
    TextEditingController m(int? v) =>
        TextEditingController(text: v == null ? '' : paiseToEditString(v));
    final custom = m(cfg.emergencyTarget);
    final monthly = m(cfg.emergencyMonthly);
    final override = m(cfg.essentialMonthly);
    int? read(TextEditingController t) =>
        t.text.trim().isEmpty ? null : parseRupeesToPaise(t.text);

    final ok = await showFormSheet(
      context,
      title: const Text('Emergency fund target'),
      submitLabel: 'Save',
      validate: () {
        if (months == null && (read(custom) ?? 0) <= 0) {
          return 'Enter your target.';
        }
        if ([
          custom,
          monthly,
          override,
        ].any((t) => t.text.trim().isNotEmpty && read(t) == null)) {
          return 'One of the amounts isn’t a number.';
        }
        return null;
      },
      builder: (context, setState) {
        final text = Theme.of(context).textTheme;
        final essential = read(override) ?? c.status?.essentialMonthly ?? 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Months of essential spending', style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final n in const [3, 6, 9, 12])
                  AppChoiceChip(
                    label: '$n months',
                    selected: months == n,
                    onTap: () => setState(() => months = n),
                  ),
                AppChoiceChip(
                  label: 'Custom amount',
                  selected: months == null,
                  onTap: () => setState(() => months = null),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (months != null)
              Text(
                essential > 0
                    ? '$months × ${formatMoney(essential, cur)} = '
                          '${formatMoney(months! * essential, cur)}'
                    : 'Set essential budgets or enter your monthly essentials below.',
                style: text.bodySmall,
              )
            else
              TextField(
                controller: custom,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Target',
                  prefixText: '$cur ',
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: override,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Essential spending per month (optional)',
                helperText:
                    'Leave blank to use ${_sourceLabel(c.essentialSource)}',
                prefixText: '$cur ',
              ),
            ),
            const SizedBox(height: AppSpacing.md - 4),
            TextField(
              controller: monthly,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Add each month (optional)',
                helperText:
                    'Smart allocation plans this until the target is met',
                prefixText: '$cur ',
              ),
            ),
          ],
        );
      },
    );
    if (!ok || !context.mounted) return;
    await c.save(
      months: months,
      customTarget: read(custom),
      monthlyContribution: read(monthly),
      essentialOverride: read(override),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EmergencyController>();
    final cur = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final s = c.status;
    String fmt(int v) => formatMoney(v, cur);
    final account = c.accounts.firstOrNull?.account.name;

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency fund')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ResponsivePage(
              builder: (context, gutter) => ListView(
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
                        Text('In your emergency fund', style: text.labelMedium),
                        Text(fmt(s.current), style: text.moneyStyle(28)),
                        if (s.target > 0) ...[
                          const SizedBox(height: AppSpacing.sm),
                          BudgetProgressBar(
                            spent: s.current.clamp(0, s.target),
                            budget: s.target,
                            color: p.income,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${s.percent}% of ${fmt(s.target)}'
                            '${s.shortfall > 0 ? ' · ${fmt(s.shortfall)} to go' : ' · target reached'}',
                            style: text.bodySmall,
                          ),
                        ],
                        if (s.coverageMonths != null)
                          Text(
                            'Covers about ${s.coverageMonths!.toStringAsFixed(1)} months of '
                            'essentials (${fmt(s.essentialMonthly)} a month, from '
                            '${_sourceLabel(c.essentialSource)}).',
                            style: text.bodySmall,
                          ),
                        if (s.shortfall > 0)
                          Text(
                            'Suggested: ${fmt(s.suggestedContribution)} a month.',
                            style: text.labelMedium?.copyWith(color: p.savings),
                          ),
                        const SizedBox(height: AppSpacing.md),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: account == null
                                    ? null
                                    : () => showTransferSheet(
                                        context,
                                        to: account,
                                        title: 'Add to emergency fund',
                                      ),
                                child: const Text('Add money'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _editTarget(context),
                                child: Text(
                                  s.target > 0 ? 'Change target' : 'Set target',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'This is the balance of your emergency accounts — the same '
                          'money in your net worth, counted once. Moving money in is '
                          'saving, not spending.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader('Accounts'),
                  if (c.accounts.isEmpty)
                    AppCard(
                      child: Text(
                        'No emergency account yet. In Accounts, give a separate savings '
                        'account the “Emergency fund” role.',
                        style: text.bodyMedium,
                      ),
                    ),
                  for (final a in c.accounts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: AppCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.account.name,
                                style: text.bodyMedium,
                              ),
                            ),
                            Text(fmt(a.worth), style: text.moneyStyle(14)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  const SectionHeader('Taken out'),
                  if (_withdrawals.isEmpty)
                    AppCard(
                      child: Text(
                        'Nothing taken out so far.',
                        style: text.bodyMedium,
                      ),
                    ),
                  for (final (date, label, amount) in _withdrawals.take(20))
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: AppCard(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${shortDate(DateTime.parse(date))} · $label',
                                style: text.bodyMedium,
                              ),
                            ),
                            Text('−${fmt(amount)}', style: text.moneyStyle(14)),
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

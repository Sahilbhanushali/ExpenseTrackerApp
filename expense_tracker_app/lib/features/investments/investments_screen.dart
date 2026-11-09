import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/account.dart';
import '../../data/repositories/investment_repository.dart';
import '../accounts/accounts_controller.dart';
import '../allocation/allocation_controller.dart';
import '../cycles/cycle_card.dart';
import '../goals/goals_controller.dart';
import '../settings/settings_controller.dart';

/// Investment accounts and the holdings you record in them. Values are
/// yours, as of the date you entered — no live prices, no promised returns.
class InvestmentsScreen extends StatefulWidget {
  final InvestmentRepository? repo;
  const InvestmentsScreen({super.key, this.repo});

  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  late final InvestmentRepository _repo = widget.repo ?? InvestmentRepository();
  List<Holding> _holdings = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await _repo.list();
    if (mounted) setState(() => _holdings = h);
  }

  Future<void> _edit(
    List<String> accounts, {
    Holding? existing,
    String? account,
  }) async {
    final cur = context.read<SettingsController>().config.currency;
    final name = TextEditingController(text: existing?.name ?? '');
    TextEditingController m(int? v) =>
        TextEditingController(text: v == null ? '' : paiseToEditString(v));
    final invested = m(existing?.investedPaise);
    final value = m(existing?.currentValuePaise);
    var kind = existing?.kind ?? HoldingKind.mutualFund;
    var acc = existing?.account ?? account ?? accounts.first;
    var asOf = existing?.asOf ?? DateTime.now();
    final ok = await showFormSheet(
      context,
      title: Text(existing == null ? 'Add holding' : 'Update holding'),
      subtitle:
          'What you hold and what it’s worth today, from your broker or app.',
      submitLabel: 'Save',
      validate: () {
        if (name.text.trim().isEmpty) return 'Name the holding.';
        if (parseRupeesToPaise(invested.text) == null) {
          return 'Enter how much you put in.';
        }
        if (parseRupeesToPaise(value.text) == null) {
          return 'Enter what it’s worth now.';
        }
        return null;
      },
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Nifty 50 index fund',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          DropdownButtonFormField<HoldingKind>(
            initialValue: kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [
              for (final k in HoldingKind.values)
                DropdownMenuItem(value: k, child: Text(holdingKindLabel(k))),
            ],
            onChanged: (v) => setState(() => kind = v ?? kind),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          DropdownButtonFormField<String>(
            initialValue: acc,
            decoration: const InputDecoration(labelText: 'Held in'),
            items: [
              for (final n in accounts)
                DropdownMenuItem(value: n, child: Text(n)),
            ],
            onChanged: (v) => setState(() => acc = v ?? acc),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: invested,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount invested',
              prefixText: '$cur ',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: value,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Current value',
              prefixText: '$cur ',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: asOf,
                firstDate: DateTime(now.year - 5),
                lastDate: now,
                helpText: 'Value as of',
              );
              if (d != null) setState(() => asOf = d);
            },
            icon: const Icon(Icons.event_rounded),
            label: Text('Value as of ${shortDate(asOf)}'),
          ),
        ],
      ),
    );
    if (!ok || !mounted) return;
    try {
      await _repo.save(
        Holding(
          id: existing?.id,
          account: acc,
          name: name.text,
          kind: kind,
          investedPaise: parseRupeesToPaise(invested.text)!,
          currentValuePaise: parseRupeesToPaise(value.text)!,
          asOf: asOf,
        ),
      );
    } on InvestmentException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    await _load();
    if (mounted) await context.read<AccountsController>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsController>();
    final cur = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    String fmt(int v) => formatMoney(v, cur);
    final invest = [
      for (final a in accounts.active)
        if (a.account.type == AccountType.investment ||
            a.account.roles.contains(AccountRole.investment))
          a,
    ];
    final names = [for (final a in invest) a.account.name];
    final planPerCycle = context.select<AllocationController, int>(
      (c) => c.config.investPerCycle ?? 0,
    );
    final longGoals = context.select<GoalsController, int>(
      (g) => g.active
          .where((x) => x.goal.horizon.name == 'long')
          .fold(0, (s, x) => s + (x.goal.monthlyContributionPaise ?? 0)),
    );
    final worth = invest.fold<int>(0, (s, a) => s + a.worth);
    final invested = _holdings.fold<int>(0, (s, h) => s + h.investedPaise);
    final value = _holdings.fold<int>(0, (s, h) => s + h.currentValuePaise);
    final waiting = invest.fold<int>(
      0,
      (s, a) => s + (a.investments?.uninvested ?? 0),
    );
    final latest = _holdings.isEmpty
        ? null
        : _holdings.map((h) => h.asOf).reduce((a, b) => a.isBefore(b) ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('Investments')),
      floatingActionButton: names.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'add_holding',
              onPressed: () => _edit(names),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add holding'),
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
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Investment accounts are worth',
                    style: text.labelMedium,
                  ),
                  Text(fmt(worth), style: text.moneyStyle(26)),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text('In holdings ${fmt(value)}', style: text.bodySmall),
                      Text('Put in ${fmt(invested)}', style: text.bodySmall),
                      Text(
                        'Cash waiting to invest ${fmt(waiting)}',
                        style: text.bodySmall,
                      ),
                      if (planPerCycle + longGoals > 0)
                        Text(
                          'Planned ${fmt(planPerCycle + longGoals)}/month',
                          style: text.bodySmall,
                        ),
                    ],
                  ),
                  if (_holdings.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${value >= invested ? 'Up' : 'Down'} ${fmt((value - invested).abs())} on paper, '
                      'using values you entered (oldest ${shortDate(latest!)}). Not a '
                      'forecast or a promise of returns.',
                      style: text.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (names.isEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Text(
                  'Add an account of type Investment (or give one the Investing '
                  'role) in Accounts, then record what you hold in it here.',
                  style: text.bodyMedium,
                ),
              ),
            ],
            for (final a in invest) ...[
              const SizedBox(height: AppSpacing.lg),
              SectionHeader(
                a.account.name,
                action: 'Add',
                onAction: () => _edit(names, account: a.account.name),
              ),
              Text(
                'Balance ${fmt(a.balance)} · worth ${fmt(a.worth)}'
                '${a.investments == null ? '' : ' · ${fmt(a.investments!.uninvested)} not yet invested'}',
                style: text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final h in _holdings.where(
                (h) => h.account == a.account.name,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: AppCard(
                    onTap: () => _edit(names, existing: h),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.name, style: text.titleSmall),
                              Text(
                                '${holdingKindLabel(h.kind)} · as of ${shortDate(h.asOf)}',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              fmt(h.currentValuePaise),
                              style: text.moneyStyle(14),
                            ),
                            Text(
                              '${h.gain >= 0 ? '+' : '−'}${fmt(h.gain.abs())}',
                              style: text.labelSmall?.copyWith(
                                color: h.gain >= 0 ? p.income : p.expense,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

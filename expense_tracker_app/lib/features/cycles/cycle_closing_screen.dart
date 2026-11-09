import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/cycle_closing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/widgets/app_chip.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/account.dart';
import '../../data/repositories/cycle_repository.dart';
import '../accounts/accounts_controller.dart';
import '../allocation/allocation_controller.dart';
import '../cards/cards_controller.dart';
import '../expenses/expenses_controller.dart';
import '../loans/loans_controller.dart';
import '../settings/settings_controller.dart';
import 'cycle_card.dart';
import 'cycle_closing_service.dart';
import 'cycle_controller.dart';

void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

Widget _row(BuildContext context, String label, String value, {Color? color}) {
  final text = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: text.bodyMedium)),
        Text(value, style: text.moneyStyle(14, color: color)),
      ],
    ),
  );
}

class _Choice {
  LeftoverKind kind;
  final TextEditingController amount;
  String? target;
  _Choice(this.kind, int paise, this.target)
    : amount = TextEditingController(text: paiseToEditString(paise));
}

/// Close an ended cycle: see where it finished, decide what happens to the
/// leftover, confirm. Nothing moves until confirmed.
class CycleClosingScreen extends StatefulWidget {
  final int cycleId;
  final CycleClosingService? service;
  const CycleClosingScreen({super.key, required this.cycleId, this.service});

  @override
  State<CycleClosingScreen> createState() => _CycleClosingScreenState();
}

class _CycleClosingScreenState extends State<CycleClosingScreen> {
  late final CycleClosingService _service =
      widget.service ?? CycleClosingService();
  ClosingPreview? _p;
  String? _source;
  String? _error;
  final _choices = <_Choice>[];
  bool _transfersDone = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final allocation = context.read<AllocationController>();
    if (allocation.view == null) await allocation.refresh();
    if (!mounted) return;
    final v = allocation.view;
    final c = context
        .read<CycleController>()
        .cycles
        .where((x) => x.record.id == widget.cycleId)
        .firstOrNull;
    if (c == null) return;
    try {
      final p = await _service.preview(
        c,
        unallocatedNow: v?.plan.available ?? 0,
        reserved: v?.reserved ?? 0,
      );
      if (mounted) {
        setState(() {
          _p = p;
          _source = v?.snapshot.sourceAccount;
        });
      }
    } on CycleException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Possible targets for [kind], as (value, label).
  List<(String, String)> _targets(LeftoverKind kind) {
    final accounts = context.read<AccountsController>().active;
    Iterable<(String, String)> withRole(AccountRole r, [AccountType? t]) =>
        accounts
            .where(
              (a) =>
                  a.account.roles.contains(r) ||
                  (t != null && a.account.type == t),
            )
            .map((a) => (a.account.name, a.account.name));
    return switch (kind) {
      LeftoverKind.savings => withRole(AccountRole.savings).toList(),
      LeftoverKind.emergency => withRole(
        AccountRole.emergency,
        AccountType.emergencyFund,
      ).toList(),
      LeftoverKind.investing => withRole(
        AccountRole.investment,
        AccountType.investment,
      ).toList(),
      LeftoverKind.custom => [
        for (final a in accounts)
          if (a.account.name != _source) (a.account.name, a.account.name),
      ],
      LeftoverKind.loanPrincipal => [
        for (final l in context.read<LoansController>().active)
          ('loan:${l.loan.id}', l.loan.name),
      ],
      LeftoverKind.cardPayment => [
        for (final c in context.read<CardsController>().cards)
          if (c.outstanding > 0) ('card:${c.card.id}', c.card.label),
      ],
      _ => const [],
    };
  }

  int get _decided =>
      _choices.fold(0, (s, c) => s + (parseRupeesToPaise(c.amount.text) ?? 0));

  List<LeftoverAction> _actions() => [
    for (final c in _choices)
      LeftoverAction(
        kind: c.kind,
        amountPaise: parseRupeesToPaise(c.amount.text) ?? 0,
        target: c.target,
        label: () {
          final t = _targets(c.kind).where((x) => x.$1 == c.target).firstOrNull;
          return t == null
              ? leftoverLabel(c.kind)
              : '${leftoverLabel(c.kind)} · ${t.$2}';
        }(),
      ),
  ];

  void _add(LeftoverKind kind, int amount) {
    final targets = _targets(kind);
    setState(() {
      _choices.add(_Choice(kind, amount, targets.firstOrNull?.$1));
      _error = null;
    });
  }

  Future<void> _confirm(String currency) async {
    final p = _p!;
    final actions = _actions();
    final error = await _service.check(p, actions, _source);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Close ${cycleLabel(p.cycle)}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actions.isEmpty)
              const Text(
                'No leftover decisions — the money stays where it is.',
              ),
            for (final a in actions) Text('• ${describeAction(a, currency)}'),
            const SizedBox(height: AppSpacing.md),
            Text(
              [
                if (actions.any((a) => movesMoney(a.kind)) && _source != null)
                  'Money moves from $_source.',
                if (!_transfersDone) 'Account transfers are saved as planned.',
                'Card and loan payments are recorded as made.',
                'The cycle’s figures are then frozen.',
              ].join(' '),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Close cycle'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.close(
        p,
        actions,
        source: _source,
        transfersDone: _transfersDone,
      );
      if (!mounted) return;
      await Future.wait([
        context.read<CycleController>().refresh(),
        context.read<AccountsController>().refresh(),
        context.read<CardsController>().refresh(),
        context.read<LoansController>().refresh(),
      ]);
      if (!mounted) return;
      await context.read<ExpensesController>().refresh();
      if (!mounted) return;
      await context.read<AllocationController>().refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
      _snack(context, 'Cycle closed. Its figures are saved as they are now.');
    } on CycleException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final pal = context.palette;
    final p = _p;
    String fmt(int v) => formatMoney(v, currency);

    return Scaffold(
      appBar: AppBar(title: const Text('Close cycle')),
      body: p == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.page),
                      child: Text(_error!, textAlign: TextAlign.center),
                    ),
            )
          : ResponsivePage(
              builder: (context, gutter) {
                final left = p.leftover - _decided;
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    AppSpacing.sm,
                    gutter,
                    AppSpacing.xl,
                  ),
                  children: [
                    Text(cycleLabel(p.cycle), style: text.titleLarge),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _row(context, 'Salary', fmt(p.income.salary)),
                          _row(
                            context,
                            'Other income',
                            fmt(p.income.additional),
                          ),
                          _row(context, 'Spent', fmt(p.spent)),
                          const Divider(),
                          _row(
                            context,
                            p.net >= 0
                                ? 'Left from this cycle'
                                : 'Spent beyond income',
                            fmt(p.net.abs()),
                            color: p.net >= 0 ? pal.income : pal.expense,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeader('Balances on ${shortDate(p.cycle.end!)}'),
                    AppCard(
                      child: Column(
                        children: [
                          for (final e in p.balances.entries)
                            _row(context, e.key, fmt(e.value)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader('Still owed'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _row(context, 'Credit cards', fmt(p.cardsOwed)),
                          _row(
                            context,
                            'Loans (principal)',
                            fmt(p.loansOutstanding),
                          ),
                          _row(
                            context,
                            'Reserved for upcoming needs',
                            fmt(p.reserved),
                          ),
                          if (p.unpaid.isNotEmpty) ...[
                            const Divider(),
                            Text(
                              'Unpaid from this cycle — they stay owed after closing:',
                              style: text.bodySmall?.copyWith(
                                color: pal.warning,
                              ),
                            ),
                            for (final e in p.unpaid.entries)
                              _row(
                                context,
                                e.key,
                                fmt(e.value),
                                color: pal.warning,
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const SectionHeader('Leftover'),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('You can decide on', style: text.labelMedium),
                          Text(
                            fmt(p.leftover),
                            style: text.moneyStyle(26, color: pal.income),
                          ),
                          Text(
                            'The smaller of what this cycle left (${fmt(p.net < 0 ? 0 : p.net)}) '
                            'and what’s unallocated in spendable accounts now '
                            '(${fmt(p.unallocatedNow < 0 ? 0 : p.unallocatedNow)}) — so the '
                            'new salary isn’t used.',
                            style: text.bodySmall,
                          ),
                          if (p.leftover > 0) ...[
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: [
                                for (final k in [
                                  LeftoverKind.carryForward,
                                  LeftoverKind.savings,
                                  LeftoverKind.emergency,
                                  LeftoverKind.cardPayment,
                                  LeftoverKind.loanPrincipal,
                                  LeftoverKind.investing,
                                  LeftoverKind.keepCash,
                                  LeftoverKind.custom,
                                ])
                                  if (!movesMoney(k) || _targets(k).isNotEmpty)
                                    AppChoiceChip(
                                      label: leftoverLabel(k),
                                      icon: Icons.add_rounded,
                                      selected: false,
                                      onTap: () => _add(k, left > 0 ? left : 0),
                                    ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    for (final (i, c) in _choices.indexed)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      leftoverLabel(c.kind),
                                      style: text.titleSmall,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove',
                                    onPressed: () =>
                                        setState(() => _choices.removeAt(i)),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                              TextField(
                                controller: c.amount,
                                onChanged: (_) => setState(() => _error = null),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: InputDecoration(
                                  labelText: 'Amount',
                                  prefixText: '$currency ',
                                ),
                              ),
                              if (movesMoney(c.kind)) ...[
                                const SizedBox(height: AppSpacing.sm),
                                DropdownButtonFormField<String>(
                                  initialValue: c.target,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'To',
                                  ),
                                  items: [
                                    for (final (v, l) in _targets(c.kind))
                                      DropdownMenuItem(
                                        value: v,
                                        child: Text(
                                          l,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => c.target = v),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    if (_choices.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        left >= 0
                            ? '${fmt(left)} of the leftover not yet decided — it stays as available cash.'
                            : '${fmt(-left)} more than the leftover.',
                        style: text.bodySmall?.copyWith(
                          color: left < 0 ? pal.expense : null,
                        ),
                      ),
                    ],
                    if (_choices.any(
                      (c) =>
                          movesMoney(c.kind) &&
                          !(c.target ?? ':').contains(':'),
                    ))
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _transfersDone,
                        onChanged: (v) => setState(() => _transfersDone = v),
                        title: const Text('Transfers already done at the bank'),
                        subtitle: Text(
                          _transfersDone ? 'Balances change now.' : 'Saved as planned; they count once marked done.',
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _error!,
                        style: text.bodyMedium?.copyWith(color: pal.expense),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _busy ? null : () => _confirm(currency),
                      child: const Text('Review and close'),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// A closed cycle, as frozen at closing.
class ClosedCycleScreen extends StatefulWidget {
  final int cycleId;
  const ClosedCycleScreen({super.key, required this.cycleId});

  @override
  State<ClosedCycleScreen> createState() => _ClosedCycleScreenState();
}

class _ClosedCycleScreenState extends State<ClosedCycleScreen> {
  int? _liveNet;

  @override
  void initState() {
    super.initState();
    final cycles = context.read<CycleController>();
    final c = cycles.cycles
        .where((x) => x.record.id == widget.cycleId)
        .firstOrNull;
    if (c != null) {
      cycles.liveSummaryFor(c).then((s) {
        if (mounted) setState(() => _liveNet = s.income.total - s.spent);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cycles = context.watch<CycleController>();
    final c = cycles.cycles
        .where((x) => x.record.id == widget.cycleId)
        .firstOrNull;
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final pal = context.palette;
    final json = c?.record.summaryJson;
    if (c == null || json == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.lock_open_rounded,
          message: 'This cycle isn’t closed.',
        ),
      );
    }
    final f = CycleCloseSummary.decode(json);
    String fmt(int v) => formatMoney(v, currency);
    final drift = _liveNet == null ? 0 : _liveNet! - f.net;

    return Scaffold(
      appBar: AppBar(
        title: Text(cycleLabel(c)),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (_) async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Reopen this cycle?'),
                  content: const Text(
                    'Its figures go back to being calculated from your transactions. '
                    'Money moved when it was closed stays moved.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Reopen'),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              try {
                await context.read<CycleController>().reopen(c.record.id!);
                if (context.mounted) Navigator.of(context).pop();
              } on CycleException catch (e) {
                if (context.mounted) _snack(context, e.message);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reopen', child: Text('Reopen cycle')),
            ],
          ),
        ],
      ),
      body: ResponsivePage(
        builder: (context, gutter) => ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            AppSpacing.sm,
            gutter,
            AppSpacing.xl,
          ),
          children: [
            Text(
              'Closed ${shortDate(f.closedAt)} — figures as they were then.',
              style: text.bodySmall,
            ),
            if (drift != 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Transactions in this cycle changed after closing; the ledger now '
                  'differs by ${fmt(drift.abs())}. Reopen to recalculate.',
                  style: text.bodySmall?.copyWith(color: pal.warning),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  _row(context, 'Salary', fmt(f.salary)),
                  _row(context, 'Other income', fmt(f.additionalIncome)),
                  _row(context, 'Spent', fmt(f.spent)),
                  const Divider(),
                  _row(
                    context,
                    f.net >= 0 ? 'Left over' : 'Overspent',
                    fmt(f.net.abs()),
                    color: f.net >= 0 ? pal.income : pal.expense,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('What you did with the leftover'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (f.actions.isEmpty)
                    Text('Left as available cash.', style: text.bodyMedium),
                  for (final a in f.actions)
                    Text(
                      '• ${describeAction(a, currency)}',
                      style: text.bodyMedium,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader('Balances on ${shortDate(f.end)}'),
            AppCard(
              child: Column(
                children: [
                  for (final e in f.balances.entries)
                    _row(context, e.key, fmt(e.value)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Owed at closing'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(context, 'Credit cards', fmt(f.cardsOwed)),
                  _row(context, 'Loans (principal)', fmt(f.loansOutstanding)),
                  for (final e in f.unpaidObligations.entries)
                    _row(context, e.key, fmt(e.value), color: pal.warning),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "The 10 Nov – 11 Dec cycle has ended — close it" with a button.
class CloseCyclePrompt extends StatelessWidget {
  final CycleRange cycle;
  const CloseCyclePrompt({super.key, required this.cycle});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pal = context.palette;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.task_alt_rounded, color: pal.savings),
          const SizedBox(width: AppSpacing.md - 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${cycleLabel(cycle)} has ended', style: text.titleSmall),
                Text(
                  'Close it to decide what to do with the leftover.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              FadeSlideRoute(
                page: CycleClosingScreen(cycleId: cycle.record.id!),
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

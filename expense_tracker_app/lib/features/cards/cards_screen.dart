import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/finance/cards.dart';
import '../../core/finance/salary_cycle.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/budget_progress_bar.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/transaction_tile.dart';
import '../../data/models/account.dart';
import '../../data/models/credit_card.dart';
import '../../data/models/transaction.dart';
import '../../data/repositories/card_repository.dart';
import '../accounts/accounts_controller.dart';
import '../accounts/reconcile_sheet.dart';
import '../cycles/cycle_card.dart';
import '../settings/settings_controller.dart';
import 'cards_controller.dart';

void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

Color stateColor(StatementState s, AppPalette p) => switch (s) {
  StatementState.paid => p.income,
  StatementState.partlyPaid => p.warning,
  StatementState.unpaid => p.savings,
  StatementState.overdue => p.expense,
};

class CardsScreen extends StatelessWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cards = context.watch<CardsController>();
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Credit cards')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add_card',
        onPressed: () => showCardForm(context),
        icon: const Icon(Icons.add_card_rounded),
        label: const Text('Add card'),
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
            if (cards.cards.isEmpty)
              AppCard(
                child: EmptyState(
                  icon: Icons.credit_card_rounded,
                  title: 'No cards yet',
                  message:
                      'Add a card to track what you owe, statements and due '
                      'dates. Paying the bill moves money from your bank to '
                      'the card — it’s never counted as spending again.',
                  action: 'Add card',
                  onAction: () => showCardForm(context),
                ),
              )
            else ...[
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Owed on cards', style: text.labelMedium),
                    ),
                    Text(
                      formatMoney(cards.outstanding, currency),
                      style: text.moneyStyle(20, color: p.expense),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final c in cards.cards)
                _CardTile(summary: c, currency: currency),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  final CardSummary summary;
  final String currency;
  const _CardTile({required this.summary, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final c = summary.card;
    final latest = summary.latest;
    final standing = latest?.standing(DateTime.now());
    final used = utilisation(summary.outstanding, c.limitPaise);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: () =>
            Navigator.of(context)
                .push(FadeSlideRoute(page: CardDetailScreen(cardId: c.id!))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.credit_card_rounded, color: p.savings),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: text.titleSmall),
                      if (c.bank != null) Text(c.bank!, style: text.bodySmall),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatMoney(summary.outstanding, currency),
                      style: text.moneyStyle(16),
                    ),
                    Text('owed', style: text.labelSmall),
                  ],
                ),
              ],
            ),
            if (c.limitPaise > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              BudgetProgressBar(
                spent: summary.outstanding.clamp(0, c.limitPaise),
                budget: c.limitPaise,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$used% of ${formatMoney(c.limitPaise, currency)} limit · '
                '${formatMoney(summary.available, currency)} available',
                style: text.bodySmall,
              ),
            ],
            if (standing != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                standing.state == StatementState.paid
                    ? 'Last statement paid'
                    : '${statementStateLabel(standing.state)}: '
                          '${formatMoney(standing.remaining, currency)} by '
                          '${shortDate(latest!.dueDate)}',
                style: text.labelMedium?.copyWith(
                  color: stateColor(standing.state, p),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CardDetailScreen extends StatefulWidget {
  final int cardId;
  const CardDetailScreen({super.key, required this.cardId});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  List<CardStatement> _statements = [];
  List<CardEmi> _emis = [];
  List<Transaction> _spending = [];
  late final CardsController _cards;

  @override
  void initState() {
    super.initState();
    _cards = context.read<CardsController>()..addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _cards.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final (s, e, t) = await (
      _cards.statements(widget.cardId),
      _cards.emis(widget.cardId),
      _cards.spending(widget.cardId),
    ).wait;
    if (mounted) {
      setState(() {
        _statements = s;
        _emis = e;
        _spending = t;
      });
    }
  }

  Future<void> _guard(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) _snack(context, done);
    } on CardException catch (e) {
      if (mounted) _snack(context, e.message);
    }
  }

  Future<void> _pay(CardSummary summary, String currency) async {
    final accounts = context.read<AccountsController>().active;
    final names = [for (final a in accounts) a.account.name];
    if (names.isEmpty) return _snack(context, 'Add a bank account first.');
    final unpaid = _statements
        .where((s) => s.standing(DateTime.now()).remaining > 0)
        .toList();
    var statement = unpaid.firstOrNull;
    String? from = names.contains(summary.card.repaymentAccount)
        ? summary.card.repaymentAccount
        : names.first;
    final amount = TextEditingController(
      text: statement == null
          ? ''
          : paiseToEditString(statement.standing(DateTime.now()).remaining),
    );
    final reference = TextEditingController();
    final ok = await showFormSheet(
      context,
      title: Text('Pay ${summary.card.name}'),
      subtitle:
          'Money moves from your bank to the card. It settles what you owe '
          'and isn’t counted as spending.',
      submitLabel: 'Record payment',
      validate: () => positiveAmountError(amount.text),
      builder: (context, setState) {
        final st = statement?.standing(DateTime.now());
        Widget preset(String label, int paise) => ActionChip(
          label: Text('$label ${formatMoneyCompact(paise, currency)}'),
          onPressed: () =>
              setState(() => amount.text = paiseToEditString(paise)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (unpaid.isNotEmpty) ...[
              DropdownButtonFormField<int?>(
                initialValue: statement?.id,
                decoration: const InputDecoration(
                  labelText: 'Toward statement',
                ),
                items: [
                  for (final s in unpaid)
                    DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '${shortDate(s.periodEnd)} · due ${shortDate(s.dueDate)}',
                      ),
                    ),
                  const DropdownMenuItem(
                    value: null,
                    child: Text('No statement (unbilled)'),
                  ),
                ],
                onChanged: (v) => setState(
                  () => statement = unpaid.where((s) => s.id == v).firstOrNull,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (st != null)
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  preset('Full', st.remaining),
                  if (st.minimumRemaining > 0)
                    preset('Minimum', st.minimumRemaining),
                ],
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                prefixText: '$currency ',
              ),
            ),
            const SizedBox(height: AppSpacing.md - 4),
            DropdownButtonFormField<String>(
              initialValue: from,
              decoration: const InputDecoration(labelText: 'Paid from'),
              items: [
                for (final n in names)
                  DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) => setState(() => from = v),
            ),
            const SizedBox(height: AppSpacing.md - 4),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
              ),
            ),
          ],
        );
      },
    );
    if (!ok || !mounted) return;
    await _guard(
      () => _cards.pay(
        cardId: widget.cardId,
        fromAccount: from!,
        amountPaise: parseRupeesToPaise(amount.text)!,
        statementId: statement?.id,
        reference: reference.text,
      ),
      'Card payment recorded.',
    );
  }

  Future<void> _addStatement(CardSummary summary, String currency) async {
    final card = summary.card;
    final now = dateOnly(DateTime.now());
    var generated = card.statementDay == null
        ? now
        : DateTime(now.year, now.month, card.statementDay!.clamp(1, 28));
    if (generated.isAfter(now)) {
      generated = DateTime(now.year, now.month - 1, generated.day);
    }
    var due = generated.add(const Duration(days: 15));
    if (card.dueDay != null) {
      due = DateTime(
        generated.year,
        generated.month,
        card.dueDay!.clamp(1, 28),
      );
      if (!due.isAfter(generated)) {
        due = DateTime(due.year, due.month + 1, due.day);
      }
    }
    var periodStart = DateTime(
      generated.year,
      generated.month - 1,
      generated.day + 1,
    );
    final c = {
      for (final k in [
        'total',
        'min',
        'prev',
        'payments',
        'refunds',
        'purchases',
        'emi',
        'charges',
        'newCharges',
      ])
        k: TextEditingController(),
    };
    final billed = <int>{
      for (final e in _emis.where((e) => !e.standing.finished)) e.id!,
    };

    int? v(String k) =>
        c[k]!.text.trim().isEmpty ? 0 : parseRupeesToPaise(c[k]!.text);
    StatementFigures figures() => StatementFigures(
      totalDue: v('total') ?? 0,
      minimumDue: v('min') ?? 0,
      previousBalance: v('prev') ?? 0,
      payments: v('payments') ?? 0,
      refunds: v('refunds') ?? 0,
      purchases: v('purchases') ?? 0,
      emiInstallments: v('emi') ?? 0,
      charges: v('charges') ?? 0,
    );

    final ok = await showFormSheet(
      context,
      title: const Text('Add statement'),
      subtitle: 'Copy the figures from your statement. They decide what’s due.',
      submitLabel: 'Save statement',
      validate: () {
        if (positiveAmountError(c['total']!.text) != null &&
            c['total']!.text.trim() != '0') {
          return 'Enter the total amount due.';
        }
        if (c.values.any(
          (t) => t.text.trim().isNotEmpty && parseRupeesToPaise(t.text) == null,
        )) {
          return 'One of the amounts isn’t a number.';
        }
        if ((v('min') ?? 0) > (v('total') ?? 0)) {
          return 'The minimum due is more than the total.';
        }
        return null;
      },
      builder: (context, setState) {
        final text = Theme.of(context).textTheme;
        Widget money(String k, String label, {String? helper}) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: TextField(
            controller: c[k],
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              prefixText: '$currency ',
            ),
          ),
        );
        Future<void> pick(String what) async {
          final initial = switch (what) {
            'gen' => generated,
            'due' => due,
            _ => periodStart,
          };
          final d = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(now.year - 2),
            lastDate: DateTime(now.year + 1),
          );
          if (d == null) return;
          setState(() {
            if (what == 'gen') generated = d;
            if (what == 'due') due = d;
            if (what == 'start') periodStart = d;
          });
        }

        final f = figures();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => pick('start'),
                  child: Text('From ${shortDate(periodStart)}'),
                ),
                OutlinedButton(
                  onPressed: () => pick('gen'),
                  child: Text('Statement ${shortDate(generated)}'),
                ),
                OutlinedButton(
                  onPressed: () => pick('due'),
                  child: Text('Due ${shortDate(due)}'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            money('total', 'Total amount due'),
            money('min', 'Minimum due'),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Statement breakdown (optional)',
                style: text.titleSmall,
              ),
              subtitle: Text(
                f.difference == 0 || f.computedDue == 0
                    ? 'Checks the statement adds up'
                    : 'Breakdown differs from the total by ${formatMoney(f.difference.abs(), currency)}',
                style: text.bodySmall,
              ),
              children: [
                money('prev', 'Previous balance'),
                money('payments', 'Payments received'),
                money('refunds', 'Refunds'),
                money('purchases', 'Purchases'),
                money('emi', 'EMI installments'),
                money('charges', 'Interest, fees & GST'),
              ],
            ),
            money(
              'newCharges',
              'New interest, fees & GST to record',
              helper: 'Counted once as an expense on the card. Skip anything already logged.',
            ),
            if (_emis.any((e) => !e.standing.finished)) ...[
              Text('EMIs on this statement', style: text.titleSmall),
              for (final e in _emis.where((e) => !e.standing.finished))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: billed.contains(e.id),
                  onChanged: (on) => setState(
                    () => on == true ? billed.add(e.id!) : billed.remove(e.id),
                  ),
                  title: Text(e.description),
                  subtitle: Text(
                    '${formatMoney(e.installment, currency)} · '
                    '${e.standing.remainingInstallments} left',
                  ),
                ),
            ],
          ],
        );
      },
    );
    if (!ok || !mounted) return;
    await _guard(
      () => _cards.addStatement(
        CardStatement(
          cardId: widget.cardId,
          periodStart: periodStart,
          periodEnd: generated,
          generatedOn: generated,
          dueDate: due,
          figures: figures(),
        ),
        billedEmis: {
          for (final id in billed) id: (principal: null, interest: null),
        },
        newCharges: v('newCharges') ?? 0,
      ),
      'Statement saved.',
    );
  }

  Future<void> _reconcile(CardSummary summary, String currency) async {
    final input = await showReconcileSheet(
      context,
      title: 'Check ${summary.card.name}',
      actualLabel: 'Owed, as the bank app shows',
      currency: currency,
      datePicker: false,
      appFigureOn: (_) async => summary.outstanding,
    );
    if (input == null || !mounted) return;
    final r = await _cards.reconcile(
      widget.cardId,
      actualOwedPaise: input.actualPaise,
      adjust: input.adjust,
      note: input.note,
    );
    if (!mounted) return;
    _snack(
      context,
      r.difference == 0
          ? 'Matches the bank.'
          : r.adjustmentMovementId != null
          ? 'Adjusted by ${formatMoney(r.difference.abs(), currency)}.'
          : 'Saved. ${formatMoney(r.difference.abs(), currency)} still to find.',
    );
  }

  Future<void> _addEmi(String currency) async {
    final purchases = _spending
        .where((t) => t.type == TxnType.expense)
        .toList();
    final onEmi = {for (final e in _emis) e.purchaseTxnId};
    final candidates = purchases.where((t) => !onEmi.contains(t.id)).toList();
    Transaction? purchase = candidates.firstOrNull;
    final installment = TextEditingController();
    final months = TextEditingController();
    final interest = TextEditingController();
    final ok = await showFormSheet(
      context,
      title: const Text('Convert a purchase to EMI'),
      subtitle:
          'The purchase stays counted once, on the day you bought it. EMIs '
          'then only track what’s billed; interest is added from statements.',
      submitLabel: 'Save EMI',
      validate: () {
        if (purchase == null) return 'Log the purchase on this card first.';
        if (positiveAmountError(installment.text) != null) {
          return 'Enter the monthly installment.';
        }
        if ((int.tryParse(months.text) ?? 0) <= 0) {
          return 'Enter the number of months.';
        }
        return null;
      },
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (candidates.isEmpty)
            const Text(
              'No purchases on this card yet. Add the expense with “Paid from” set to this card.',
            )
          else
            DropdownButtonFormField<int>(
              initialValue: purchase?.id,
              decoration: const InputDecoration(labelText: 'Purchase'),
              isExpanded: true,
              items: [
                for (final t in candidates)
                  DropdownMenuItem(
                    value: t.id,
                    child: Text(
                      '${t.note ?? t.category} · ${formatMoney(t.amountPaise, currency)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(
                () => purchase = candidates.firstWhere((t) => t.id == v),
              ),
            ),
          const SizedBox(height: AppSpacing.md - 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: installment,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Monthly installment',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: months,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Months'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: interest,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Total interest (optional)',
              helperText: 'Only if the bank told you',
            ),
          ),
        ],
      ),
    );
    if (!ok || !mounted) return;
    final p = purchase!;
    await _guard(
      () => _cards.addEmi(
        CardEmi(
          cardId: widget.cardId,
          purchaseTxnId: p.id,
          description: p.note ?? p.category,
          purchaseAmount: p.amountPaise,
          purchaseDate: DateTime.parse(p.date),
          tenureMonths: int.parse(months.text),
          installment: parseRupeesToPaise(installment.text)!,
          interestTotal: interest.text.trim().isEmpty
              ? null
              : parseRupeesToPaise(interest.text),
        ),
      ),
      'EMI saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = context.watch<CardsController>();
    final summary = cards.cards
        .where((c) => c.card.id == widget.cardId)
        .firstOrNull;
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          message: 'This card is gone.',
        ),
      );
    }
    final c = summary.card;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(c.label),
        actions: [
          IconButton(
            tooltip: 'Edit card',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showCardForm(context, existing: c),
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
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Owed on this card', style: text.labelMedium),
                  Text(
                    formatMoney(summary.outstanding, currency),
                    style: text.moneyStyle(26),
                  ),
                  if (c.limitPaise > 0)
                    Text(
                      '${formatMoney(summary.available, currency)} of '
                      '${formatMoney(c.limitPaise, currency)} available',
                      style: text.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _pay(summary, currency),
                          child: const Text('Pay bill'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _addStatement(summary, currency),
                          child: const Text('Add statement'),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => _reconcile(summary, currency),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Check against bank app'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Statements'),
            if (_statements.isEmpty)
              AppCard(
                child: Text('No statements yet.', style: text.bodyMedium),
              ),
            for (final s in _statements)
              Builder(
                builder: (context) {
                  final st = s.standing(today);
                  final diff = s.figures.computedDue == 0
                      ? 0
                      : s.figures.difference;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: AppCard(
                      onTap: st.paid == 0
                          ? () async {
                              final del = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  title: const Text('Delete this statement?'),
                                  content: const Text(
                                    'Also removes the charges it recorded. Only possible before any payment.',
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
                              if (del == true) {
                                await _guard(
                                  () => _cards.removeStatement(s.id!),
                                  'Statement deleted.',
                                );
                              }
                            }
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${shortDate(s.periodStart)} – ${shortDate(s.periodEnd)}',
                                  style: text.titleSmall,
                                ),
                              ),
                              Text(
                                statementStateLabel(st.state),
                                style: text.labelMedium?.copyWith(
                                  color: stateColor(st.state, p),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Due ${shortDate(s.dueDate)} · total ${formatMoney(s.figures.totalDue, currency)}'
                            ' · min ${formatMoney(s.figures.minimumDue, currency)}',
                            style: text.bodySmall,
                          ),
                          Text(
                            'Paid ${formatMoney(st.paid, currency)} · left ${formatMoney(st.remaining, currency)}',
                            style: text.bodySmall,
                          ),
                          if (diff != 0)
                            Text(
                              'Breakdown differs from the total by ${formatMoney(diff.abs(), currency)}',
                              style: text.bodySmall?.copyWith(color: p.warning),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(
              'Card EMIs',
              action: 'Convert purchase',
              onAction: () => _addEmi(currency),
            ),
            if (_emis.isEmpty)
              AppCard(
                child: Text(
                  'None. Bought something big on this card? Convert it to EMI.',
                  style: text.bodyMedium,
                ),
              ),
            for (final e in _emis)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(e.description, style: text.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      BudgetProgressBar(
                        spent: e.billed,
                        budget: e.tenureMonths,
                        color: p.income,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${e.billed} of ${e.tenureMonths} billed · '
                        '${formatMoney(e.installment, currency)}/month · '
                        '${formatMoney(e.standing.remainingPayable, currency)} still to be billed',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Recent spending on this card'),
            if (_spending.isEmpty)
              AppCard(
                child: Text(
                  'Nothing yet. When adding an expense, set “Paid from” to this card.',
                  style: text.bodyMedium,
                ),
              )
            else
              TransactionGroup(
                children: [
                  for (final t in _spending.take(10))
                    TransactionTile(txn: t, currency: currency, showDate: true),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Add or edit a card. Only the last four digits are ever asked for.
Future<void> showCardForm(BuildContext context, {CreditCard? existing}) async {
  final controller = context.read<CardsController>();
  final accounts = [
    for (final a in context.read<AccountsController>().active)
      if (a.account.isSpendable || a.account.roles.contains(AccountRole.emi))
        a.account.name,
  ];
  final name = TextEditingController(text: existing?.name ?? '');
  final bank = TextEditingController(text: existing?.bank ?? '');
  final last4 = TextEditingController(text: existing?.last4 ?? '');
  final limit = TextEditingController(
    text: existing == null ? '' : paiseToEditString(existing.limitPaise),
  );
  final opening = TextEditingController(
    text: existing == null
        ? ''
        : paiseToEditString(existing.openingOutstandingPaise),
  );
  int? statementDay = existing?.statementDay;
  int? dueDay = existing?.dueDay;
  String? repay = accounts.contains(existing?.repaymentAccount)
      ? existing?.repaymentAccount
      : accounts.firstOrNull;

  CreditCard build() => CreditCard(
    id: existing?.id,
    name: name.text.trim(),
    bank: bank.text.trim().isEmpty ? null : bank.text.trim(),
    last4: last4.text.trim().isEmpty ? null : last4.text.trim(),
    limitPaise: parseRupeesToPaise(limit.text) ?? 0,
    openingOutstandingPaise: parseRupeesToPaise(opening.text) ?? 0,
    statementDay: statementDay,
    dueDay: dueDay,
    repaymentAccount: repay,
  );

  final ok = await showFormSheet(
    context,
    title: Text(existing == null ? 'Add credit card' : 'Edit card'),
    subtitle: 'Never enter the full card number, CVV, PIN or OTP — only the last 4 digits.',
    submitLabel: existing == null ? 'Add card' : 'Save',
    validate: () {
      if (name.text.trim().isEmpty) return 'Give the card a name.';
      final d = last4.text.trim();
      if (d.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(d)) {
        return 'Last 4 digits only.';
      }
      if (parseRupeesToPaise(limit.text) == null) {
        return 'Enter the credit limit.';
      }
      if (opening.text.trim().isNotEmpty &&
          parseRupeesToPaise(opening.text) == null) {
        return 'Enter the current balance as a number.';
      }
      return null;
    },
    builder: (context, setState) {
      DropdownButtonFormField<int?> day(
        String label,
        int? value,
        ValueChanged<int?> on,
      ) => DropdownButtonFormField<int?>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(value: null, child: Text('—')),
          for (var d = 1; d <= 31; d++)
            DropdownMenuItem(value: d, child: Text('$d')),
        ],
        onChanged: on,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Card name',
              hintText: 'e.g. HDFC Millennia',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: bank,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Bank'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: last4,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Last 4',
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Credit limit'),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          TextField(
            controller: opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Owed on it right now',
              helperText: 'Starting balance — not counted as new spending',
            ),
          ),
          const SizedBox(height: AppSpacing.md - 4),
          Row(
            children: [
              Expanded(
                child: day(
                  'Statement day',
                  statementDay,
                  (v) => setState(() => statementDay = v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: day(
                  'Due day',
                  dueDay,
                  (v) => setState(() => dueDay = v),
                ),
              ),
            ],
          ),
          if (accounts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md - 4),
            DropdownButtonFormField<String>(
              initialValue: repay,
              decoration: const InputDecoration(labelText: 'Usually paid from'),
              items: [
                for (final n in accounts)
                  DropdownMenuItem(value: n, child: Text(n)),
              ],
              onChanged: (v) => setState(() => repay = v),
            ),
          ],
        ],
      );
    },
  );
  if (!ok || !context.mounted) return;
  try {
    await controller.save(build());
  } on CardException catch (e) {
    if (context.mounted) _snack(context, e.message);
  }
}

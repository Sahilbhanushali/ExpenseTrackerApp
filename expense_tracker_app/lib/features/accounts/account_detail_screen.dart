import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/page_transitions.dart';
import '../../core/widgets/responsive.dart';
import '../../core/widgets/section_header.dart';
import '../../data/models/account.dart';
import '../../data/repositories/reconciliation_repository.dart';
import '../cycles/cycle_card.dart';
import '../expenses/transactions_screen.dart';
import '../settings/settings_controller.dart';
import 'accounts_controller.dart';
import 'reconcile_sheet.dart';

void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(m)));

/// "Matched bank · 9 Nov", "₹1,200 off since 9 Nov", or null if never checked.
String? checkLabel(Reconciliation? r, String currency) {
  if (r == null) return null;
  if (r.matched) return 'Matched bank · ${shortDate(r.asOf)}';
  return '${formatMoney(r.difference.abs(), currency)} off bank · ${shortDate(r.asOf)}';
}

/// Records money moving between two of your accounts, now or as planned.
/// [planned] transfers wait (and change no balance) until marked done.
Future<void> showTransferSheet(
  BuildContext context, {
  String? from,
  String? to,
  String? title,
}) async {
  final controller = context.read<AccountsController>();
  final names = [for (final a in controller.active) a.account.name];
  if (names.length < 2) {
    _snack(context, 'Add at least two accounts first.');
    return;
  }
  var src = names.contains(from) ? from! : names.first;
  var dst = names.contains(to) && to != src
      ? to!
      : names.firstWhere((n) => n != src);
  final amount = TextEditingController();
  final note = TextEditingController();
  var done = true;
  final ok = await showFormSheet(
    context,
    title: Text(title ?? 'Transfer'),
    subtitle: 'Between your own accounts — never income or spending.',
    submitLabel: 'Save transfer',
    validate: () =>
        positiveAmountError(amount.text) ??
        (src == dst ? 'Pick two different accounts.' : null),
    builder: (context, setState) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: src,
          decoration: const InputDecoration(labelText: 'From'),
          items: [
            for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
          ],
          onChanged: (v) => setState(() => src = v ?? src),
        ),
        const SizedBox(height: AppSpacing.md - 4),
        DropdownButtonFormField<String>(
          initialValue: dst,
          decoration: const InputDecoration(labelText: 'To'),
          items: [
            for (final n in names) DropdownMenuItem(value: n, child: Text(n)),
          ],
          onChanged: (v) => setState(() => dst = v ?? dst),
        ),
        const SizedBox(height: AppSpacing.md - 4),
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount'),
        ),
        const SizedBox(height: AppSpacing.md - 4),
        TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: done,
          onChanged: (v) => setState(() => done = v),
          title: const Text('Already done at the bank'),
          subtitle: Text(
            done
                ? 'Both balances change now.'
                : 'Saved as planned. Balances change when you mark it done.',
          ),
        ),
      ],
    ),
  );
  if (!ok || !context.mounted) return;
  final paise = parseRupeesToPaise(amount.text)!;
  final n = note.text.trim().isEmpty ? null : note.text.trim();
  if (done) {
    await controller.transfer(src, dst, paise, n);
  } else {
    await controller.planTransfer(src, dst, paise, n);
  }
}

Future<void> reconcileAccount(BuildContext context, MoneyAccount a) async {
  final controller = context.read<AccountsController>();
  final currency = context.read<SettingsController>().config.currency;
  final input = await showReconcileSheet(
    context,
    title: 'Check ${a.name} against the bank',
    actualLabel: 'Balance the bank shows',
    currency: currency,
    appFigureOn: (d) async => await controller.balanceAsOf(a.name, d) ?? 0,
  );
  if (input == null || !context.mounted) return;
  final r = await controller.reconcile(
    a.name,
    asOf: input.asOf,
    actualPaise: input.actualPaise,
    adjust: input.adjust,
    note: input.note,
  );
  if (!context.mounted) return;
  _snack(
    context,
    r.difference == 0
        ? 'Matches the bank.'
        : r.adjustmentMovementId != null
        ? 'Adjusted by ${formatMoney(r.difference.abs(), currency)}.'
        : 'Saved. ${formatMoney(r.difference.abs(), currency)} still to find.',
  );
}

class AccountDetailScreen extends StatefulWidget {
  final int accountId;
  const AccountDetailScreen({super.key, required this.accountId});

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  List<Reconciliation> _checks = [];
  late final AccountsController _accounts;

  @override
  void initState() {
    super.initState();
    _accounts = context.read<AccountsController>()..addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _accounts.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final a = _accounts.accounts
        .where((x) => x.account.id == widget.accountId)
        .firstOrNull;
    if (a == null) return;
    final checks = await _accounts.checks(a.account);
    if (mounted) setState(() => _checks = checks);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsController>();
    final ab = accounts.accounts
        .where((x) => x.account.id == widget.accountId)
        .firstOrNull;
    final currency = context.select<SettingsController, String>(
      (s) => s.config.currency,
    );
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    if (ab == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          message: 'This account is gone.',
        ),
      );
    }
    final a = ab.account;
    final cash = accounts.active
        .where(
          (x) => x.account.bankType == BankType.cash && x.account.id != a.id,
        )
        .firstOrNull;
    final planned = accounts.planned
        .where((t) => t.fromAccount == a.name || t.toAccount == a.name)
        .toList();
    final check = checkLabel(accounts.lastCheck(a), currency);
    final details = [
      if (a.bankType != null) bankTypeLabel(a.bankType!),
      if (a.bankName != null) a.bankName!,
      if (a.last4 != null) '••${a.last4}',
    ].join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(a.name)),
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
                  Text('Balance', style: text.labelMedium),
                  Text(
                    formatMoney(ab.balance, currency),
                    style: text.moneyStyle(28),
                  ),
                  if (a.holdPaise > 0)
                    Text(
                      '${formatMoney(ab.balance - a.holdPaise, currency)} available · '
                      '${formatMoney(a.holdPaise, currency)} on hold',
                      style: text.bodySmall,
                    ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(details, style: text.bodySmall),
                  ],
                  if (a.roles.isNotEmpty)
                    Text(
                      a.roles.map(accountRoleLabel).join(', '),
                      style: text.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    check ?? 'Never checked against the bank',
                    style: text.labelMedium?.copyWith(
                      color: accounts.lastCheck(a)?.matched == false
                          ? p.warning
                          : p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.icon(
                    onPressed: () => reconcileAccount(context, a),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Check against bank'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () =>
                            showTransferSheet(context, from: a.name),
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Transfer'),
                      ),
                      if (cash != null) ...[
                        OutlinedButton(
                          onPressed: () => showTransferSheet(
                            context,
                            from: cash.account.name,
                            to: a.name,
                            title: 'Deposit cash',
                          ),
                          child: const Text('Deposit'),
                        ),
                        OutlinedButton(
                          onPressed: () => showTransferSheet(
                            context,
                            from: a.name,
                            to: cash.account.name,
                            title: 'Withdraw cash',
                          ),
                          child: const Text('Withdraw'),
                        ),
                      ],
                    ],
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      FadeSlideRoute(page: TransactionsScreen(account: a.name)),
                    ),
                    child: const Text('See all transactions'),
                  ),
                ],
              ),
            ),
            if (planned.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const SectionHeader('Waiting at the bank'),
              for (final t in planned)
                PlannedTransferRow(transfer: t, currency: currency),
            ],
            const SizedBox(height: AppSpacing.lg),
            const SectionHeader('Bank checks'),
            if (_checks.isEmpty)
              AppCard(
                child: Text(
                  'Check this balance against your bank app or passbook now '
                  'and then. Every check is kept here.',
                  style: text.bodyMedium,
                ),
              ),
            for (final r in _checks.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        r.difference == 0
                            ? Icons.check_circle_rounded
                            : r.adjustmentMovementId != null
                            ? Icons.tune_rounded
                            : Icons.error_outline,
                        size: AppIconSize.md,
                        color: r.matched ? p.income : p.warning,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(shortDate(r.asOf), style: text.bodyMedium),
                            Text(
                              r.difference == 0
                                  ? 'Matched'
                                  : '${r.adjustmentMovementId != null ? 'Adjusted' : 'Off'} by '
                                        '${formatMoney(r.difference.abs(), currency)}'
                                        '${r.note == null ? '' : ' · ${r.note}'}',
                              style: text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(r.actualBalance, currency),
                        style: text.moneyStyle(14),
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

/// A planned transfer with Done / Cancel.
class PlannedTransferRow extends StatelessWidget {
  final Transfer transfer;
  final String currency;
  const PlannedTransferRow({
    super.key,
    required this.transfer,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final controller = context.read<AccountsController>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${transfer.fromAccount} → ${transfer.toAccount}',
                    style: text.titleSmall,
                  ),
                  Text(
                    '${formatMoney(transfer.amountPaise, currency)} · planned '
                    '${shortDate(DateTime.parse(transfer.date))}'
                    '${transfer.note == null ? '' : ' · ${transfer.note}'}',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => controller.cancelMovement(transfer.id!),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => controller.completeTransfer(transfer.id!),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

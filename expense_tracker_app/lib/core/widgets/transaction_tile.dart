import 'package:flutter/material.dart';

import '../../data/models/transaction.dart';
import '../constants/calendar.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../utils/money_formatter.dart';
import 'category_icon.dart';

/// Compact transaction row: category badge, title + subtitle, signed amount.
/// Draws no surface of its own — place rows inside an [AppCard] (see
/// [TransactionGroup]) so a day's rows read as one block.
class TransactionTile extends StatelessWidget {
  final Transaction txn;
  final String currency;
  final VoidCallback? onTap;

  /// Shows the date in the subtitle (for lists not grouped by day).
  final bool showDate;

  const TransactionTile({
    super.key,
    required this.txn,
    required this.currency,
    this.onTap,
    this.showDate = false,
  });

  bool get _isCredit =>
      txn.type == TxnType.income || txn.type == TxnType.borrowed;
  bool get _isLending =>
      txn.type == TxnType.lent || txn.type == TxnType.borrowed;

  String get _subtitle {
    final base = _isLending
        ? (txn.type == TxnType.lent
              ? '${txn.counterparty ?? 'They'} owe${txn.counterparty == null ? '' : 's'} you'
              : 'You owe ${txn.counterparty ?? 'them'}')
        : _capitalize(txn.category);
    if (!showDate) return base;
    final d = DateTime.tryParse(txn.date);
    if (d == null) return base;
    return '$base · ${d.day} ${kMonthNamesShort[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    // Lending moves cash but isn't income/expense — a borrowed amount is a
    // debt, not earnings — so it gets its own colour.
    final amountColor = _isLending
        ? p.warning
        : (_isCredit ? p.income : p.textPrimary);
    final sign = _isCredit ? '+' : '−';
    final title = txn.note?.isNotEmpty == true
        ? txn.note!
        : _capitalize(txn.category);
    final amount = '$sign${formatMoney(txn.amountPaise, currency)}';
    final kind = switch (txn.type) {
      TxnType.expense => 'Expense',
      TxnType.income => 'Income',
      TxnType.lent => 'Lent',
      TxnType.borrowed => 'Borrowed',
    };

    return Semantics(
      button: onTap != null,
      label: '$kind, $title, $_subtitle, $amount',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              CategoryIcon(
                category: _isLending ? 'lending' : txn.category,
                icon: txn.type == TxnType.income
                    ? CategoryStyle.of('income').icon
                    : null,
                color: txn.type == TxnType.income ? p.income : null,
              ),
              const SizedBox(width: AppSpacing.md - 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: _isLending ? p.warning : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Long amounts at large text sizes shrink rather than push the
              // row past the screen edge.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    amount,
                    style: text.moneyStyle(15, color: amountColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// Rows inside one card separated by inset hairlines.
class TransactionGroup extends StatelessWidget {
  final List<Widget> children;
  const TransactionGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                indent: AppSpacing.md + AppSizes.iconBadge + 12,
                endIndent: AppSpacing.md,
                color: p.border,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

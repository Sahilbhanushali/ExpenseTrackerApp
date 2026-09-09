import 'package:flutter/material.dart';

import '../../data/models/transaction.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/money_formatter.dart';
import 'press_scale.dart';

class TransactionTile extends StatelessWidget {
  final Transaction txn;
  final String currency;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.txn,
    required this.currency,
    this.onTap,
  });

  bool get _isCredit =>
      txn.type == TxnType.income || txn.type == TxnType.borrowed;
  bool get _isLending =>
      txn.type == TxnType.lent || txn.type == TxnType.borrowed;

  @override
  Widget build(BuildContext context) {
    // Lending entries move cash in/out but aren't real income/expense — a
    // borrowed amount is a debt you still owe, not money you've earned, so
    // it gets its own colour instead of looking identical to income.
    final color = _isLending
        ? AppColors.warning
        : (_isCredit ? AppColors.income : AppColors.expense);
    final sign = _isCredit ? '+' : '-';
    final catColor = _isLending
        ? AppColors.warning
        : AppColors.categoryColor(txn.category);

    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(_iconFor(txn.category), color: catColor, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    txn.note?.isNotEmpty == true ? txn.note! : txn.category,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isLending
                        ? (txn.type == TxnType.lent
                              ? '${txn.counterparty ?? 'They'} owe${txn.counterparty == null ? '' : 's'} you'
                              : 'You owe ${txn.counterparty ?? 'them'}')
                        : txn.category,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _isLending ? AppColors.warning : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$sign${formatMoney(txn.amountPaise, currency)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String category) {
    switch (category) {
      case 'travel':
        return Icons.directions_car_outlined;
      case 'food':
        return Icons.restaurant_outlined;
      case 'groceries':
        return Icons.shopping_basket_outlined;
      case 'clothes':
        return Icons.checkroom_outlined;
      case 'rent':
        return Icons.home_outlined;
      case 'bills':
        return Icons.receipt_long_outlined;
      case 'luxuries':
        return Icons.local_bar_outlined;
      case 'fitness':
        return Icons.fitness_center_outlined;
      case 'investments':
        return Icons.trending_up_outlined;
      case 'health':
        return Icons.local_hospital_outlined;
      case 'education':
        return Icons.school_outlined;
      case 'lending':
        return Icons.handshake_outlined;
      case 'income':
        return Icons.arrow_downward_outlined;
      default:
        return Icons.category_outlined;
    }
  }
}

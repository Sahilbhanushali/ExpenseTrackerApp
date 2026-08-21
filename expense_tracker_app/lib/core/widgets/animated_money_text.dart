import 'package:flutter/material.dart';

import '../utils/money_formatter.dart';

/// Counts up/down to `amount` whenever it changes, instead of jumping —
/// gives dashboard totals and balances a sense of live movement.
class AnimatedMoneyText extends StatelessWidget {
  final double amount;
  final String currency;
  final TextStyle? style;

  const AnimatedMoneyText({
    super.key,
    required this.amount,
    required this.currency,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amount),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text(formatMoney(value, currency), style: style);
      },
    );
  }
}

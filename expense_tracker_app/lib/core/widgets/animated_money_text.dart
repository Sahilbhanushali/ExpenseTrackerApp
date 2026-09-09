import 'package:flutter/material.dart';

import '../utils/money_formatter.dart';

/// Counts up/down to `amountPaise` whenever it changes, instead of jumping
/// — gives dashboard totals and balances a sense of live movement. The
/// tween runs over a double for smoothness, but only whole paise are ever
/// rendered.
class AnimatedMoneyText extends StatelessWidget {
  /// In paise.
  final int amountPaise;
  final String currency;
  final TextStyle? style;

  const AnimatedMoneyText({
    super.key,
    required this.amountPaise,
    required this.currency,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amountPaise.toDouble()),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text(formatMoney(value.round(), currency), style: style);
      },
    );
  }
}

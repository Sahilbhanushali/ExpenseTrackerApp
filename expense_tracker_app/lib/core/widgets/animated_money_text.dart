import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../utils/money_formatter.dart';

/// Counts to `amountPaise` whenever it changes instead of jumping. The tween
/// runs over a double for smoothness, but only whole paise are rendered.
class AnimatedMoneyText extends StatelessWidget {
  /// In paise.
  final int amountPaise;
  final String currency;
  final TextStyle? style;

  /// Replaces the figure with dots (privacy toggle).
  final bool masked;

  const AnimatedMoneyText({
    super.key,
    required this.amountPaise,
    required this.currency,
    this.style,
    this.masked = false,
  });

  @override
  Widget build(BuildContext context) {
    if (masked) {
      return Text(
        '$currency • • • • •',
        style: style,
        semanticsLabel: 'Amount hidden',
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: amountPaise.toDouble()),
      duration: AppDurations.of(context, AppDurations.counter),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Text(
          formatMoney(value.round(), currency),
          style: style,
          maxLines: 1,
          // Screen readers get the final value, not every intermediate tick.
          semanticsLabel: formatMoney(amountPaise, currency),
        );
      },
    );
  }
}

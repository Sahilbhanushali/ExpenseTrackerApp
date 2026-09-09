import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../core/widgets/animated_money_text.dart';

class HeroCard extends StatelessWidget {
  /// All in paise.
  final int spent;
  final int budget;
  final int remaining;
  final String currency;

  const HeroCard({
    super.key,
    required this.spent,
    required this.budget,
    required this.remaining,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl), // bigger padding
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl), // larger radius
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spent this month',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          AnimatedMoneyText(
            amountPaise: spent,
            currency: currency,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48, // chunkier
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
            ),
          ).animate().fadeIn().scaleXY(
            begin: 0.9,
            end: 1.0,
            duration: 300.ms,
            curve: Curves.easeOutBack,
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child:
                LinearProgressIndicator(
                  value: budget > 0 ? (spent / budget).clamp(0.0, 1.0) : 0,
                  minHeight: 12,
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ).animate().slideX(
                  begin: -1,
                  duration: 500.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Budget ${formatMoney(budget, currency)}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                remaining >= 0
                    ? '${formatMoney(remaining, currency)} left'
                    : '${formatMoney(remaining.abs(), currency)} over',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

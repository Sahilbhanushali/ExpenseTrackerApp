import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_money_text.dart';

class StatCard extends StatelessWidget {
  final String label;

  /// In paise.
  final int? value;
  final String currency;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    // The purple tint is only readable on a light card — on the dark
    // background (near-black) it needs a much lighter tone, or the label
    // and amount both disappear against the tinted backdrop.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? const Color(0xFFDBAFFF) : AppColors.primary;
    final valueColor = isDark ? Colors.white : AppColors.primaryDark;
    return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: labelColor, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              value == null
                  ? Text('—', style: Theme.of(context).textTheme.titleMedium)
                  : AnimatedMoneyText(
                      amountPaise: value!,
                      currency: currency,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: valueColor,
                      ),
                    ),
            ],
          ),
        )
        .animate()
        .slideY(begin: 0.5, duration: 400.ms, curve: Curves.easeOutBack)
        .fadeIn();
  }
}

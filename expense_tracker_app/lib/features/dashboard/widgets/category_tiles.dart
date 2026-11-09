import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/category_icon.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/money_formatter.dart';

/// Deepened so white labels on a solid category tile stay legible.
Color tileColor(Color c) => Color.lerp(c, Colors.black, 0.2)!;

/// Category split as a proportional bar plus solid tiles for the biggest
/// categories. The bar covers every category; tiles show the top ones.
class CategoryTiles extends StatelessWidget {
  /// Category → paise.
  final Map<String, int> totals;
  final String currency;

  const CategoryTiles({
    super.key,
    required this.totals,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (s, e) => s + e.value);
    if (total == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 560 ? 4 : 2;
        final shown = entries.take(columns * 2).toList();
        final tileWidth =
            (c.maxWidth - AppSpacing.sm * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SpendBar(entries: entries, total: total),
            const SizedBox(height: AppSpacing.md - 4),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final e in shown)
                  SizedBox(
                    width: tileWidth,
                    child: _CategoryTile(
                      category: e.key,
                      amount: e.value,
                      percent: (e.value / total * 100).round(),
                      currency: currency,
                    ),
                  ),
              ],
            ),
            if (entries.length > shown.length) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '+${entries.length - shown.length} more categories',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A single rounded bar split into each category's share.
class SpendBar extends StatelessWidget {
  final List<MapEntry<String, int>> entries;
  final int total;
  final double height;

  const SpendBar({
    super.key,
    required this.entries,
    required this.total,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Spending split: ${entries.take(4).map((e) => '${e.key} ${(e.value / total * 100).round()} percent').join(', ')}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (var i = 0; i < entries.length; i++)
                Expanded(
                  // Flex needs ints; per-mille keeps tiny slices visible.
                  flex: (entries[i].value / total * 1000).round().clamp(
                    1,
                    1000,
                  ),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: i == entries.length - 1 ? 0 : 2,
                    ),
                    color: AppColors.categoryColor(entries[i].key),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String category;
  final int amount;
  final int percent;
  final String currency;

  const _CategoryTile({
    required this.category,
    required this.amount,
    required this.percent,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = category.isEmpty
        ? category
        : '${category[0].toUpperCase()}${category.substring(1)}';
    return Semantics(
      label: '$name, ${formatMoney(amount, currency)}, $percent percent',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md - 4),
        decoration: BoxDecoration(
          // A soft tint of the category colour with normal text on it:
          // readable in both themes, unlike white text on bright fills.
          color: Color.alphaBlend(
            style.color.withValues(alpha: dark ? 0.2 : 0.1),
            p.surface,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryIcon(category: category, size: 34, solid: true),
                const Spacer(),
                Text(
                  '$percent%',
                  style: text.labelMedium?.copyWith(color: p.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatMoney(amount, currency),
                style: text.moneyStyle(17, color: p.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

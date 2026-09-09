import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money_formatter.dart';

class CategoryChart extends StatefulWidget {
  /// Category → paise.
  final Map<String, int> totals;
  final String currency;
  const CategoryChart({
    super.key,
    required this.totals,
    required this.currency,
  });

  @override
  State<CategoryChart> createState() => CategoryChartState();
}

class CategoryChartState extends State<CategoryChart> {
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final entries = widget.totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    final touchedIndex = _touchedIndex;
    final highlighted =
        touchedIndex != null &&
            touchedIndex >= 0 &&
            touchedIndex < entries.length
        ? entries[touchedIndex]
        : null;

    // The chart's actual painted diameter is 2 * (centerSpaceRadius +
    // sectionRadius), not whatever box it's given — fl_chart draws at
    // these absolute radii regardless of the parent's size, so the box
    // around it has to be sized to fit the largest possible radius (the
    // touched state) or the circle paints outside its own card.
    const centerSpaceRadius = 48.0;
    const sectionRadius = 48.0;
    const touchedSectionRadius = 54.0;
    const chartBoxSize = (centerSpaceRadius + touchedSectionRadius) * 2 + 8;

    return Column(
      children: [
        SizedBox(
          height: chartBoxSize,
          width: chartBoxSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: centerSpaceRadius,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      if (!event.isInterestedForInteractions ||
                          response?.touchedSection == null) {
                        setState(() => _touchedIndex = null);
                        return;
                      }
                      setState(
                        () => _touchedIndex =
                            response!.touchedSection!.touchedSectionIndex,
                      );
                    },
                  ),
                  sections: List.generate(entries.length, (i) {
                    final e = entries[i];
                    final pct = total > 0 ? e.value / total * 100 : 0.0;
                    final isTouched = i == _touchedIndex;
                    // Slivers under ~8% can't fit a readable label without
                    // the text clipping into neighboring slices — omit it
                    // rather than let it overlap.
                    final showTitle = pct >= 8 || isTouched;
                    return PieChartSectionData(
                      value: e.value.toDouble(),
                      color: AppColors.categoryColor(e.key),
                      title: showTitle ? '${pct.round()}%' : '',
                      radius: isTouched ? touchedSectionRadius : sectionRadius,
                      titlePositionPercentageOffset: 0.62,
                      titleStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    );
                  }),
                ),
              ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: highlighted != null
                    ? Column(
                        key: ValueKey(highlighted.key),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            highlighted.key,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            formatMoney(highlighted.value, widget.currency),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('total'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            formatMoney(total, widget.currency),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...entries.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.categoryColor(e.key),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(e.key)),
                Text(formatMoney(e.value, widget.currency)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Per-category budget adherence for the viewed month — only shows
/// categories that actually have a budget set (via the budget planner).

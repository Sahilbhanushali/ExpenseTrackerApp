import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money_formatter.dart';

/// Donut of category share. Touch a slice to see its name and amount in the
/// centre; otherwise the centre shows the total.
class CategoryChart extends StatefulWidget {
  /// Category → paise.
  final Map<String, int> totals;
  final String currency;
  final double size;

  const CategoryChart({
    super.key,
    required this.totals,
    required this.currency,
    this.size = 200,
  });

  @override
  State<CategoryChart> createState() => CategoryChartState();
}

class CategoryChartState extends State<CategoryChart> {
  int? _touchedIndex;
  late List<MapEntry<String, int>> _entries;
  late int _total;

  @override
  void initState() {
    super.initState();
    _derive();
  }

  @override
  void didUpdateWidget(CategoryChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.totals != widget.totals) {
      _derive();
      _touchedIndex = null;
    }
  }

  /// Sorted once per data change, not on every touch rebuild.
  void _derive() {
    _entries = widget.totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _total = _entries.fold<int>(0, (sum, e) => sum + e.value);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = context.palette;
    final touched = _touchedIndex;
    final highlighted =
        touched != null && touched >= 0 && touched < _entries.length
        ? _entries[touched]
        : null;

    // fl_chart paints at absolute radii regardless of the box, so the box is
    // sized for the largest (touched) radius.
    final ring = widget.size * 0.16;
    final centre = widget.size / 2 - ring - 6;

    return Semantics(
      label:
          'Category breakdown, total ${formatMoney(_total, widget.currency)}',
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              duration: AppDurations.of(context, AppDurations.chart),
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: centre,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    final idx = response?.touchedSection?.touchedSectionIndex;
                    final next = event.isInterestedForInteractions ? idx : null;
                    if (next != _touchedIndex) {
                      setState(() => _touchedIndex = next);
                    }
                  },
                ),
                sections: List.generate(_entries.length, (i) {
                  final e = _entries[i];
                  return PieChartSectionData(
                    value: e.value.toDouble(),
                    color: AppColors.categoryColor(e.key),
                    showTitle: false,
                    radius: i == _touchedIndex ? ring + 6 : ring,
                  );
                }),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(ring + AppSpacing.md),
              child: AnimatedSwitcher(
                duration: AppDurations.of(context, AppDurations.fast),
                child: Column(
                  key: ValueKey(highlighted?.key ?? '_total'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      highlighted?.key ?? 'Total spent',
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatMoney(
                          highlighted?.value ?? _total,
                          widget.currency,
                        ),
                        style: text.moneyStyle(18),
                      ),
                    ),
                    if (highlighted != null && _total > 0)
                      Text(
                        '${(highlighted.value / _total * 100).round()}%',
                        style: text.labelMedium?.copyWith(
                          color: p.textSecondary,
                        ),
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

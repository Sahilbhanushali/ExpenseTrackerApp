import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/calendar.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../data/repositories/transaction_repository.dart';

/// Income vs. expense per month, oldest to newest — answers "am I trending
/// up or down" at a glance. Tap a month for exact figures.
class TrendChart extends StatelessWidget {
  final List<MonthPoint> points;
  final String currency;
  final double height;

  const TrendChart({
    super.key,
    required this.points,
    required this.currency,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final maxVal = points.fold<int>(0, (m, e) {
      final hi = e.income > e.expense ? e.income : e.expense;
      return hi > m ? hi : m;
    });
    final ceiling = maxVal <= 0 ? 1.0 : maxVal * 1.15;

    String label(int i) {
      final parts = points[i].month.split('-');
      return kMonthNamesShort[int.parse(parts[1]) - 1];
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              ChartLegendDot(color: p.income, label: 'Income'),
              ChartLegendDot(color: p.expense, label: 'Expenses'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: height,
          child: BarChart(
            duration: AppDurations.of(context, AppDurations.chart),
            BarChartData(
              maxY: ceiling,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: ceiling / 4,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: p.border, strokeWidth: 1, dashArray: [4, 4]),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    interval: ceiling / 4,
                    getTitlesWidget: (v, meta) {
                      if (v == 0 || v >= ceiling) return const SizedBox();
                      return Text(
                        formatMoneyCompact(v.round(), currency),
                        style: text.labelSmall,
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= points.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm - 2),
                        child: Text(label(i), style: text.labelSmall),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => p.inkSurface,
                  tooltipRoundedRadius: AppRadius.xs,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                        '${label(group.x)} · ${rodIndex == 0 ? 'Income' : 'Spent'}\n',
                        text.labelSmall!.copyWith(color: p.onInkMuted),
                        children: [
                          TextSpan(
                            text: formatMoney(rod.toY.round(), currency),
                            style: text.labelMedium?.copyWith(color: p.onInk),
                          ),
                        ],
                      ),
                ),
              ),
              barGroups: List.generate(points.length, (i) {
                final pt = points[i];
                const radius = BorderRadius.vertical(top: Radius.circular(4));
                return BarChartGroupData(
                  x: i,
                  barsSpace: 4,
                  barRods: [
                    BarChartRodData(
                      toY: pt.income.toDouble(),
                      color: p.income,
                      width: 10,
                      borderRadius: radius,
                    ),
                    BarChartRodData(
                      toY: pt.expense.toDouble(),
                      color: p.expense,
                      width: 10,
                      borderRadius: radius,
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class ChartLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const ChartLegendDot({super.key, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: AppSpacing.sm - 2),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

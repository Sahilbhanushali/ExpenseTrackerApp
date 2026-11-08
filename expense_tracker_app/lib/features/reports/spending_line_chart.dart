import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/money_formatter.dart';

/// One point on the spending line: a label for the axis/tooltip and the
/// bucket's total in paise.
class SpendPoint {
  final String axisLabel;
  final String tooltipLabel;
  final int paise;
  const SpendPoint(this.axisLabel, this.tooltipLabel, this.paise);
}

/// Spending over time as a line with a soft fill. Touch to scrub; the
/// tooltip shows the bucket's exact total.
class SpendingLineChart extends StatelessWidget {
  final List<SpendPoint> points;
  final String currency;
  final double height;

  const SpendingLineChart({
    super.key,
    required this.points,
    required this.currency,
    this.height = 200,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final line = p.savings;
    final maxVal = points.fold<int>(0, (m, e) => e.paise > m ? e.paise : m);
    final ceiling = maxVal <= 0 ? 1.0 : maxVal * 1.2;
    // Roughly five axis labels whatever the range length.
    final step = (points.length / 5).ceil().clamp(1, 1000);

    return SizedBox(
      height: height,
      child: LineChart(
        duration: AppDurations.of(context, AppDurations.chart),
        LineChartData(
          minY: 0,
          maxY: ceiling,
          minX: 0,
          maxX: (points.length - 1).toDouble().clamp(1, double.infinity),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: ceiling / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: p.border, strokeWidth: 1, dashArray: [4, 4]),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
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
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (v != i || i < 0 || i >= points.length) {
                    return const SizedBox();
                  }
                  if (i % step != 0 && i != points.length - 1) {
                    return const SizedBox();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm - 2),
                    child: Text(points[i].axisLabel, style: text.labelSmall),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (bar, idx) => idx
                .map(
                  (_) => TouchedSpotIndicatorData(
                    FlLine(
                      color: line.withValues(alpha: 0.5),
                      strokeWidth: 1,
                      dashArray: [4, 4],
                    ),
                    FlDotData(
                      getDotPainter: (s, d, b, i) => FlDotCirclePainter(
                        radius: 5,
                        color: line,
                        strokeWidth: 2,
                        strokeColor: p.surface,
                      ),
                    ),
                  ),
                )
                .toList(),
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => p.inkSurface,
              tooltipRoundedRadius: AppRadius.xs,
              getTooltipItems: (spots) => spots.map((s) {
                final pt = points[s.x.round()];
                return LineTooltipItem(
                  '${formatMoney(pt.paise, currency)}\n',
                  text.labelMedium!.copyWith(color: p.onInk),
                  children: [
                    TextSpan(
                      text: pt.tooltipLabel,
                      style: text.labelSmall?.copyWith(
                        color: p.onInk.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].paise.toDouble()),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              curveSmoothness: 0.2,
              color: line,
              barWidth: 2.5,
              dotData: FlDotData(show: points.length <= 12),
              belowBarData: BarAreaData(
                show: true,
                color: line.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

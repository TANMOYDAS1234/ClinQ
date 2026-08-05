import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/glucose_trends.dart';

/// The contract's `GET /glucose/trends` does not publish a target-range
/// threshold, so this chart shades the widely-used general glucose target
/// band (70-180 mg/dL) purely as a visual reference; the authoritative
/// per-reading flag still comes from the server (`reading.flag`).
const double _targetLow = 70;
const double _targetHigh = 180;

class GlucoseTrendChart extends StatelessWidget {
  const GlucoseTrendChart({super.key, required this.trends});

  final GlucoseTrends trends;

  @override
  Widget build(BuildContext context) {
    final points = trends.series;
    if (points.length < 2) {
      return const SizedBox.shrink();
    }

    final values = points.map((p) => p.value.toDouble()).toList();
    final minY = (values.reduce((a, b) => a < b ? a : b) - 30).clamp(0, double.infinity).toDouble();
    final maxY = values.reduce((a, b) => a > b ? a : b) + 30;

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: minY < _targetLow - 30 ? minY : (_targetLow - 30).toDouble(),
          maxY: maxY > _targetHigh + 30 ? maxY : (_targetHigh + 30).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 50,
            getDrawingHorizontalLine: (value) =>
                FlLine(color: Theme.of(context).colorScheme.outlineVariant, strokeWidth: 0.5),
          ),
          rangeAnnotations: RangeAnnotations(
            horizontalRangeAnnotations: [
              HorizontalRangeAnnotation(
                y1: _targetLow,
                y2: _targetHigh,
                color: AppColors.successOn(context).withValues(alpha: 0.10),
              ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: 50,
                getTitlesWidget: (value, meta) =>
                    Text(value.toInt().toString(), style: const TextStyle(fontSize: 11)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: (points.length / 4).clamp(1, double.infinity).toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  final at = points[i].at;
                  if (at == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(DateFormat('d/M').format(at.toLocal()), style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots.map((s) {
                return LineTooltipItem('${s.y.toInt()} mg/dL', const TextStyle(color: Colors.white));
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value.toDouble())],
              isCurved: true,
              curveSmoothness: 0.2,
              color: AppColors.accentOn(context),
              barWidth: 2.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

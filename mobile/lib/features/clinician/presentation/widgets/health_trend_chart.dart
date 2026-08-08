import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/patient_summary.dart';

/// The general glucose target band (70-180 mg/dL) shaded purely as a visual
/// reference — the same band the patient's own chart uses.
const double _targetLow = 70;
const double _targetHigh = 180;

/// The doctor's continuous-monitoring graph for one patient: an AGP-style view
/// of the glucose series — a daily-average line riding inside the day's
/// low→high spread band, over the shaded target range. Reads the per-day
/// summary the summary endpoint already returns (`trends.daily`), so it needs
/// no extra call.
class HealthTrendChart extends StatelessWidget {
  const HealthTrendChart({super.key, required this.daily});

  final List<GlucoseDailyPoint> daily;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);

    // A single day can't make a trend; keep the record clean until there are
    // at least two points to draw a line between.
    if (daily.length < 2) {
      return _Frame(
        scheme: scheme,
        accent: accent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.show_chart_rounded, color: scheme.onSurfaceVariant, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  daily.isEmpty
                      ? 'No glucose readings yet. The graph fills in as the patient checks in.'
                      : 'One reading so far — the trend appears after the next check-in.',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final mins = daily.map((d) => d.min.toDouble()).toList();
    final maxs = daily.map((d) => d.max.toDouble()).toList();
    final lowest = mins.reduce((a, b) => a < b ? a : b);
    final highest = maxs.reduce((a, b) => a > b ? a : b);

    // Keep the target band in view even when every reading sits well inside it.
    final minY = ((lowest < _targetLow ? lowest : _targetLow) - 20).clamp(0, double.infinity).toDouble();
    final maxY = (highest > _targetHigh ? highest : _targetHigh) + 20;
    final lastIndex = daily.length - 1;

    return _Frame(
      scheme: scheme,
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: lastIndex.toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 60,
                  getDrawingHorizontalLine: (v) =>
                      FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 0.5),
                ),
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    HorizontalRangeAnnotation(
                      y1: _targetLow,
                      y2: _targetHigh,
                      color: AppColors.successOn(context).withValues(alpha: 0.09),
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: 60,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: (daily.length / 4).clamp(1, double.infinity).toDouble(),
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= daily.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(DateFormat('d/M').format(daily[i].date),
                              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => scheme.inverseSurface,
                    getTooltipItems: (spots) => spots.map((s) {
                      // Only annotate the average line (bar index 2); the band
                      // edges would just repeat noise.
                      if (s.barIndex != 2) return null;
                      final d = daily[s.x.toInt()];
                      return LineTooltipItem(
                        '${d.average} mg/dL\n',
                        TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w700, fontSize: 13),
                        children: [
                          TextSpan(
                            text: 'range ${d.min}–${d.max} · ${DateFormat('d MMM').format(d.date)}',
                            style: TextStyle(color: scheme.onInverseSurface.withValues(alpha: 0.75), fontWeight: FontWeight.w400, fontSize: 11),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                // Bars 0/1 are the invisible spread edges; bar 2 is the average.
                betweenBarsData: [
                  BetweenBarsData(fromIndex: 0, toIndex: 1, color: accent.withValues(alpha: 0.11)),
                ],
                lineBarsData: [
                  _edge([for (var i = 0; i < daily.length; i++) FlSpot(i.toDouble(), daily[i].min.toDouble())]),
                  _edge([for (var i = 0; i < daily.length; i++) FlSpot(i.toDouble(), daily[i].max.toDouble())]),
                  LineChartBarData(
                    spots: [for (var i = 0; i < daily.length; i++) FlSpot(i.toDouble(), daily[i].average.toDouble())],
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: accent,
                    barWidth: 2.6,
                    belowBarData: BarAreaData(show: false),
                    dotData: FlDotData(
                      // Emphasise only the latest point — where the patient is now.
                      checkToShowDot: (spot, _) => spot.x == lastIndex.toDouble(),
                      getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                        radius: 4.5,
                        color: accent,
                        strokeWidth: 2.5,
                        strokeColor: scheme.surface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _LegendDot(color: accent, label: 'Daily average'),
              const SizedBox(width: 14),
              _LegendDot(color: accent.withValues(alpha: 0.28), label: 'Low–high range', square: true),
              const SizedBox(width: 14),
              _LegendDot(color: AppColors.successOn(context).withValues(alpha: 0.35), label: 'Target 70–180', square: true),
            ],
          ),
        ],
      ),
    );
  }

  /// An invisible line whose only job is to bound the shaded spread band.
  static LineChartBarData _edge(List<FlSpot> spots) => LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.2,
        barWidth: 0,
        color: Colors.transparent,
        dotData: const FlDotData(show: false),
      );
}

/// The card chrome shared by the chart and its empty state.
class _Frame extends StatelessWidget {
  const _Frame({required this.scheme, required this.accent, required this.child});

  final ColorScheme scheme;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.monitor_heart_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Glucose monitoring', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.square = false});

  final Color color;
  final String label;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: square ? 9 : 11,
          decoration: BoxDecoration(
            color: color,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(2) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

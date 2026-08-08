import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../domain/clinician_models.dart';
import 'sparkline.dart';

/// The population charts for the doctor's home — clinic-wide aggregates, never
/// 100 patient lines. Three cards: how the whole clinic's control is trending,
/// how risk is distributed, and who to look at first.

// ---------------------------------------------------------------------------
// Shared card chrome
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, this.subtitle, required this.child});

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
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
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(subtitle!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

Widget _emptyHint(BuildContext context, String text) {
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Row(
      children: [
        Icon(Icons.insights_rounded, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant))),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// 1. Clinic glucose-control trend (100% stacked area: low / in-range / high)
// ---------------------------------------------------------------------------

class ClinicControlTrendCard extends StatelessWidget {
  const ClinicControlTrendCard({super.key, required this.analytics});

  final ClinicAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final low = AppColors.dangerOn(context);
    final inRange = AppColors.successOn(context);
    final high = AppColors.warningOn(context);

    // Only days that actually have readings; a no-reading day carries no
    // proportion and would otherwise read as "all high".
    final pts = analytics.controlTrend.where((p) => p.total > 0).toList();

    // Don't draw a trend from a handful of readings — a jumpy line off 5 points
    // reads as signal when it's noise.
    final tooThin = pts.length < 3 || analytics.totalReadings < 15;

    final subtitle = analytics.totalReadings == 0
        ? null
        : '${analytics.totalReadings} readings · last ${analytics.controlTrend.length} days';

    return _Card(
      icon: Icons.insights_rounded,
      title: 'Clinic glucose control',
      subtitle: subtitle,
      child: tooThin
          ? _emptyHint(context, 'Not enough readings yet — the clinic trend fills in as patients check in.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 170, child: _StackedArea(pts: pts, low: low, inRange: inRange, high: high)),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _LegendDot(color: inRange, label: 'In range'),
                    _LegendDot(color: high, label: 'High'),
                    _LegendDot(color: low, label: 'Low'),
                  ],
                ),
                // Is monitoring actually happening? Distinct patients logging
                // each day — a flat-low line means the clinic isn't checking in.
                if (analytics.engagement.length >= 2) ...[
                  const SizedBox(height: AppSpacing.md),
                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(Icons.how_to_reg_rounded, size: 16, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Patients checking in / day',
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ),
                      Sparkline(
                        values: [for (final e in analytics.engagement) e.patients.toDouble()],
                        color: AppColors.accentOn(context),
                        width: 84,
                        height: 22,
                        showBand: false,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _StackedArea extends StatelessWidget {
  const _StackedArea({required this.pts, required this.low, required this.inRange, required this.high});

  final List<ControlPoint> pts;
  final Color low;
  final Color inRange;
  final Color high;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Cumulative fractions: bottom band = low, then +in-range, top always 1.
    double lowFrac(int i) => pts[i].low / pts[i].total;
    double midCum(int i) => (pts[i].low + pts[i].inRange) / pts[i].total;

    LineChartBarData band(double Function(int) y, Color color) => LineChartBarData(
          spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), y(i))],
          isCurved: true,
          curveSmoothness: 0.15,
          barWidth: 0,
          color: color,
          dotData: const FlDotData(show: false),
        );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (pts.length - 1).toDouble(),
        minY: 0,
        maxY: 1,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.35), strokeWidth: 0.5),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 0.25,
              getTitlesWidget: (v, _) => Text('${(v * 100).round()}%',
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (pts.length / 4).clamp(1, double.infinity).toDouble(),
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= pts.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat('d/M').format(pts[i].date),
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        // Bars: 0 = low edge, 1 = low+inRange edge, 2 = top (1.0). Fills stack.
        betweenBarsData: [
          BetweenBarsData(fromIndex: 0, toIndex: 1, color: inRange.withValues(alpha: 0.55)),
          BetweenBarsData(fromIndex: 1, toIndex: 2, color: high.withValues(alpha: 0.5)),
        ],
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), lowFrac(i))],
            isCurved: true,
            curveSmoothness: 0.15,
            barWidth: 0,
            color: low,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: low.withValues(alpha: 0.55)),
          ),
          band(midCum, inRange),
          LineChartBarData(
            spots: [for (var i = 0; i < pts.length; i++) FlSpot(i.toDouble(), 1)],
            barWidth: 0,
            color: Colors.transparent,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Risk distribution donut
// ---------------------------------------------------------------------------

class RiskDonutCard extends StatelessWidget {
  const RiskDonutCard({super.key, required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final low = AppColors.successOn(context);
    final moderate = AppColors.warningOn(context);
    final high = const Color(0xFFF97316); // orange, between warning and danger
    final critical = AppColors.dangerOn(context);

    final segments = <(String, int, Color)>[
      ('Low', overview.riskLow, low),
      ('Moderate', overview.riskModerate, moderate),
      ('High', overview.riskHigh, high),
      ('Critical', overview.riskCritical, critical),
    ];
    final total = segments.fold(0, (s, e) => s + e.$2);

    return _Card(
      icon: Icons.donut_large_rounded,
      title: 'Risk distribution',
      subtitle: total > 0 ? '$total patients' : null,
      child: total == 0
          ? _emptyHint(context, 'No risk data yet.')
          : Row(
              children: [
                SizedBox(
                  width: 118,
                  height: 118,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 34,
                          startDegreeOffset: -90,
                          sections: [
                            for (final s in segments)
                              if (s.$2 > 0)
                                PieChartSectionData(
                                  value: s.$2.toDouble(),
                                  color: s.$3,
                                  radius: 22,
                                  showTitle: false,
                                ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1)),
                          Text('patients', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in segments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              _dot(s.$3),
                              const SizedBox(width: 8),
                              Expanded(child: Text(s.$1, style: const TextStyle(fontSize: 13.5))),
                              Text('${s.$2}',
                                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dot(Color c) => Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

// ---------------------------------------------------------------------------
// 3. Top-N "needs attention" with sparklines
// ---------------------------------------------------------------------------

class AttentionListCard extends StatelessWidget {
  const AttentionListCard({super.key, required this.patients, this.max = 6});

  final List<PatientListItem> patients;
  final int max;

  @override
  Widget build(BuildContext context) {
    // Rank: open alerts first, then risk score, then most overdue.
    final ranked = [...patients]..sort((a, b) {
        final alert = b.openAlertCount.compareTo(a.openAlertCount);
        if (alert != 0) return alert;
        final risk = b.riskScore.compareTo(a.riskScore);
        if (risk != 0) return risk;
        return (b.checkInOverdue ? 1 : 0).compareTo(a.checkInOverdue ? 1 : 0);
      });
    final top = ranked.take(max).toList();

    return _Card(
      icon: Icons.priority_high_rounded,
      title: 'Needs attention',
      subtitle: top.isEmpty ? null : 'Highest-priority patients first',
      child: top.isEmpty
          ? _emptyHint(context, 'No patients flagged right now.')
          : Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  _AttentionRow(patient: top[i]),
                ],
              ],
            ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.patient});

  final PatientListItem patient;

  String _ago(DateTime at) {
    final d = DateTime.now().difference(at).inDays;
    if (d <= 0) return 'today';
    if (d == 1) return '1d';
    if (d < 21) return '${d}d';
    return '${(d / 7).round()}w';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final riskColor = switch (patient.riskBand) {
      'critical' => AppColors.dangerOn(context),
      'high' => const Color(0xFFF97316),
      'moderate' => AppColors.warningOn(context),
      _ => AppColors.successOn(context),
    };

    return InkWell(
      onTap: () => context.push('/clinician/patients/${patient.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            UserAvatar(name: patient.name, avatarUrl: patient.avatarUrl, accent: riskColor, size: 38),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(patient.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  // Wrap, not Row: the risk chip + alerts + recency must never
                  // clip on a narrow phone; they flow to a second line instead.
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: riskColor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
                        child: Text(patient.riskBand,
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: riskColor)),
                      ),
                      if (patient.openAlertCount > 0)
                        Text('${patient.openAlertCount} alert${patient.openAlertCount == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 11.5, color: AppColors.dangerOn(context), fontWeight: FontWeight.w600)),
                      if (patient.lastReadingAt != null)
                        Text('· ${_ago(patient.lastReadingAt!)}',
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (patient.spark.length >= 2)
              Sparkline(values: patient.spark, color: AppColors.accentOn(context), width: 56, height: 22),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 11, height: 11, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

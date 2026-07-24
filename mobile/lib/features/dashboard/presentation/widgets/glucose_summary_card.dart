import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/dashboard_data.dart';

class GlucoseSummaryCard extends StatelessWidget {
  const GlucoseSummaryCard({super.key, required this.glucose});

  final DashboardGlucose glucose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final latest = glucose.latest;
    final color = latest == null ? AppColors.primary : AppColors.forGlucoseFlag(latest.flag);

    return AppCard(
      onTap: () => context.go('/track'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bloodtype_rounded, color: color, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.dashboardGlucoseLatest, style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (latest == null)
            Text(
              '—',
              style: Theme.of(context).textTheme.headlineMedium,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${latest.value}',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 6),
                Text('mg/dL', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          if (glucose.sparkline.length >= 2)
            SizedBox(
              height: 56,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < glucose.sparkline.length; i++)
                          FlSpot(i.toDouble(), glucose.sparkline[i].value.toDouble()),
                      ],
                      isCurved: true,
                      color: color,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _StatChip(
                  label: l10n.dashboardGlucoseAverage,
                  value: glucose.sevenDayAverage == null
                      ? '—'
                      : '${glucose.sevenDayAverage} mg/dL',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatChip(
                  label: l10n.dashboardTimeInRange,
                  value: glucose.timeInRangePercent == null
                      ? '—'
                      : '${glucose.timeInRangePercent}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

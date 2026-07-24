import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/glucose_trends.dart';

class GlucoseStatsRow extends StatelessWidget {
  const GlucoseStatsRow({super.key, required this.stats});

  final GlucoseStats stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: l10n.glucoseStatsAverage, value: _fmt(stats.average, 'mg/dL')),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatCard(label: l10n.glucoseStatsMin, value: _fmt(stats.min, 'mg/dL'))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatCard(label: l10n.glucoseStatsMax, value: _fmt(stats.max, 'mg/dL'))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(label: l10n.glucoseStatsHba1c, value: _fmt(stats.estimatedHba1c, '%')),
        ),
      ],
    );
  }

  String _fmt(num? value, String unit) => value == null ? '—' : '$value $unit';
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

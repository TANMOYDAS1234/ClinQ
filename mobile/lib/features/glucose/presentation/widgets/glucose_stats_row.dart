import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/providers/preferences_provider.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/glucose_trends.dart';

class GlucoseStatsRow extends ConsumerWidget {
  const GlucoseStatsRow({super.key, required this.stats});

  final GlucoseStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final unit = ref.watch(glucoseUnitProvider);
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: l10n.glucoseStatsAverage, value: _glucose(unit, stats.average)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatCard(label: l10n.glucoseStatsMin, value: _glucose(unit, stats.min))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatCard(label: l10n.glucoseStatsMax, value: _glucose(unit, stats.max))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatCard(label: l10n.glucoseStatsHba1c, value: _fmt(stats.estimatedHba1c, '%')),
        ),
      ],
    );
  }

  // HbA1c is a percentage, so it keeps its own formatter; the three glucose
  // stats follow the patient's chosen unit.
  String _glucose(GlucoseUnit unit, num? value) => value == null ? '—' : unit.format(value);

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

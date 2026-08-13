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

    // A 2×2 grid, not a 4-across row: four cards on a phone squeezed each one so
    // hard that "239 mg/dL" truncated to "239 …" and "Estimated HbA1c" wrapped
    // mid-word. Half the width each — matching the fact grid above — gives every
    // value and label room to read in full. (The estimate is derived from the
    // recent readings, so its label says so, to set it apart from a lab HbA1c.)
    final cards = <Widget>[
      _StatCard(label: l10n.glucoseStatsAverage, value: _glucose(unit, stats.average)),
      _StatCard(label: l10n.glucoseStatsMin, value: _glucose(unit, stats.min)),
      _StatCard(label: l10n.glucoseStatsMax, value: _glucose(unit, stats.max)),
      _StatCard(label: l10n.glucoseStatsHba1c, value: _estHba1c(stats.estimatedHba1c)),
    ];

    return Column(
      children: [
        for (var i = 0; i < cards.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: cards[i]),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // HbA1c is a percentage, so it keeps its own formatter; the three glucose
  // stats follow the patient's chosen unit.
  String _glucose(GlucoseUnit unit, num? value) => value == null ? '—' : unit.format(value);

  // The "~" marks it as an ESTIMATE derived from recent glucose, so it reads
  // apart from the exact lab "Last HbA1c" on the home fact grid — the two used
  // to look like two conflicting measurements of the same thing.
  String _estHba1c(num? value) => value == null ? '—' : '~$value%';
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

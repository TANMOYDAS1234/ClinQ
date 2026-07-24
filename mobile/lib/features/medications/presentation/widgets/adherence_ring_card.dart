import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/health_ring.dart';
import '../../domain/medication.dart';

class AdherenceRingCard extends StatelessWidget {
  const AdherenceRingCard({super.key, required this.adherence});

  final MedicationAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      child: Row(
        children: [
          HealthRing(
            value: adherence.percentage.toDouble(),
            color: AppColors.primary,
            size: 96,
            strokeWidth: 11,
            centerLabel: '${adherence.percentage.round()}%',
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.medsAdherence, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(l10n.medsLast30Days, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${adherence.taken} / ${adherence.expected}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

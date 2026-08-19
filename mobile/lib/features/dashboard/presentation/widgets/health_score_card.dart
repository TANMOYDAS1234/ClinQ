import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/health_ring.dart';
import '../../domain/dashboard_data.dart';

class HealthScoreCard extends StatelessWidget {
  const HealthScoreCard({super.key, required this.healthScore});

  final HealthScore healthScore;

  Color _bandColor(String band) {
    switch (band.toLowerCase()) {
      case 'excellent':
      case 'good':
        return AppColors.success;
      case 'fair':
        return AppColors.warning;
      case 'poor':
      case 'critical':
        return AppColors.danger;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = _bandColor(healthScore.band);
    return AppCard(
      child: Row(
        children: [
          HealthRing(
            value: healthScore.score.toDouble(),
            color: color,
            size: 108,
            strokeWidth: 12,
            centerLabel: '${healthScore.score}',
            centerSubLabel: '/ 100',
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.dashboardHealthScore, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    healthScore.band,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/health_ring.dart';
import '../../domain/dashboard_data.dart';

class AdherenceTile extends StatelessWidget {
  const AdherenceTile({super.key, required this.adherence});

  final DashboardAdherence adherence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AppCard(
      onTap: () => context.go('/track'),
      child: Row(
        children: [
          HealthRing(
            value: adherence.percentage.toDouble(),
            color: AppColors.primary,
            size: 76,
            strokeWidth: 9,
            centerLabel: '${adherence.percentage.round()}%',
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.dashboardAdherence, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                if (adherence.todayPending > 0)
                  Text(
                    l10n.dashboardTodayPending(adherence.todayPending),
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.warning),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline),
        ],
      ),
    );
  }
}

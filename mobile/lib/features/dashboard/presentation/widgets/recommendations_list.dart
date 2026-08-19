import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/dashboard_data.dart';

class RecommendationsList extends StatelessWidget {
  const RecommendationsList({super.key, required this.recommendations});

  final List<DashboardRecommendation> recommendations;

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'high':
        return AppColors.danger;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.dashboardRecommendations, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        if (recommendations.isEmpty)
          AppCard(
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: AppColors.successOn(context)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(l10n.dashboardNoRecommendations)),
              ],
            ),
          )
        else
          ...recommendations.map(
            (rec) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _priorityColor(rec.priority),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rec.title,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 0),
                          Text(rec.body, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

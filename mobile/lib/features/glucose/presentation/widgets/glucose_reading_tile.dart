import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../domain/glucose_reading.dart';

class GlucoseReadingTile extends StatelessWidget {
  const GlucoseReadingTile({super.key, required this.reading, this.onDelete});

  final GlucoseReading reading;
  final VoidCallback? onDelete;

  String _contextLabel(AppLocalizations l10n, String context) {
    switch (context) {
      case 'fasting':
        return l10n.glucoseContextFasting;
      case 'pre_meal':
        return l10n.glucoseContextPreMeal;
      case 'post_meal':
        return l10n.glucoseContextPostMeal;
      case 'bedtime':
        return l10n.glucoseContextBedtime;
      default:
        return l10n.glucoseContextRandom;
    }
  }

  String _flagLabel(AppLocalizations l10n, String flag) {
    switch (flag) {
      case 'severe_low':
        return l10n.glucoseFlagSevereLow;
      case 'low':
        return l10n.glucoseFlagLow;
      case 'very_high':
        return l10n.glucoseFlagVeryHigh;
      case 'critical_high':
        return l10n.glucoseFlagCriticalHigh;
      default:
        return l10n.glucoseFlagInRange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = AppColors.forGlucoseFlag(reading.flag);

    return Dismissible(
      key: ValueKey(reading.id),
      direction: onDelete == null ? DismissDirection.none : DismissDirection.endToStart,
      confirmDismiss: (_) async {
        if (onDelete == null) return false;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            content: Text(l10n.glucoseDeleteConfirm),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.commonDelete)),
            ],
          ),
        );
        return confirmed ?? false;
      },
      onDismissed: (_) => onDelete?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.dangerBg,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '${reading.valueMgDl}',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      Text('mg/dL', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _contextLabel(l10n, reading.context),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (reading.measuredAt != null)
                    Text(
                      DateFormat('d MMM, h:mm a').format(reading.measuredAt!.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _flagLabel(l10n, reading.flag),
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

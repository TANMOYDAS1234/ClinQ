import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../domain/dashboard_data.dart';

class NextAppointmentCard extends StatelessWidget {
  const NextAppointmentCard({super.key, required this.appointment});

  final NextAppointment? appointment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appt = appointment;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.dashboardNextAppointment, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  appt == null || appt.scheduledFor == null
                      ? l10n.dashboardNoAppointment
                      : DateFormat('EEE, d MMM · h:mm a').format(appt.scheduledFor!.toLocal()),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (appt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${appt.mode} · ${appt.status}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

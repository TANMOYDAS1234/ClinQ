import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';

class _CareItem {
  const _CareItem({
    required this.icon,
    required this.color,
    required this.titleBuilder,
    required this.descBuilder,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String Function(AppLocalizations) titleBuilder;
  final String Function(AppLocalizations) descBuilder;
  final String route;
}

final _items = <_CareItem>[
  _CareItem(
    icon: Icons.forum_rounded,
    color: AppColors.success,
    titleBuilder: (l) => l.careMessageClinic,
    descBuilder: (l) => l.careMessageClinicDesc,
    route: '/care/messages',
  ),
  _CareItem(
    icon: Icons.event_available_outlined,
    color: AppColors.primary,
    titleBuilder: (l) => l.careAppointments,
    descBuilder: (l) => l.careAppointmentsDesc,
    route: '/care/appointments',
  ),
  _CareItem(
    icon: Icons.directions_walk_rounded,
    color: AppColors.primary,
    titleBuilder: (l) => l.careFootCare,
    descBuilder: (l) => l.careFootCareDesc,
    route: '/care/foot',
  ),
  _CareItem(
    icon: Icons.visibility_outlined,
    color: AppColors.warning,
    titleBuilder: (l) => l.careEyeCare,
    descBuilder: (l) => l.careEyeCareDesc,
    route: '/care/eye',
  ),
  _CareItem(
    icon: Icons.receipt_long_outlined,
    color: AppColors.primary,
    titleBuilder: (l) => l.carePrescriptions,
    descBuilder: (l) => l.carePrescriptionsDesc,
    route: '/care/prescriptions',
  ),
  _CareItem(
    icon: Icons.science_outlined,
    color: AppColors.danger,
    titleBuilder: (l) => l.careLabReports,
    descBuilder: (l) => l.careLabReportsDesc,
    route: '/care/labs',
  ),
];

/// Bottom-nav "Care" tab: navigation hub only. The five destination
/// screens are placeholders ("coming next") per this task's scope — see
/// `CarePlaceholderScreen`.
class CareScreen extends StatelessWidget {
  const CareScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.careTitle), automaticallyImplyLeading: false),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final item = _items[index];
          return AppCard(
            onTap: () => context.push(item.route),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.titleBuilder(l10n),
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(item.descBuilder(l10n), style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.outline),
              ],
            ),
          );
        },
      ),
    );
  }
}

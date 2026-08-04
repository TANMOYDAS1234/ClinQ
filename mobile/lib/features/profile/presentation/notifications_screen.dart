import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/services/notification_service.dart';
import '../../medications/presentation/medications_providers.dart';

/// Notification preference toggles. They record intent — push delivery to the
/// device is still being set up server-side, which the note makes plain.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    final prefs = ref.watch(appPreferencesProvider);
    final controller = ref.read(appPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileNotifications)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Medicine reminders are real, on-device alarms scheduled from
                // the dose schedule; this switch arms or silences them. (Only
                // appointment reminders stay absent — that feature is gone.)
                _tile(
                  context,
                  accent: accent,
                  icon: Icons.medication_outlined,
                  title: 'Medicine reminders',
                  subtitle: 'Alarm before each dose',
                  value: prefs.medicationReminders,
                  onChanged: (v) {
                    controller.setMedicationReminders(v);
                    if (v) {
                      refreshAndScheduleMedicationReminders(ref).catchError((_) {});
                    } else {
                      NotificationService.instance.cancelMedicationReminders();
                    }
                  },
                ),
                _tile(
                  context,
                  accent: accent,
                  icon: Icons.local_hospital_outlined,
                  title: l10n.notifClinicAlerts,
                  subtitle: l10n.notifClinicAlertsSub,
                  value: prefs.clinicAlerts,
                  onChanged: controller.setClinicAlerts,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.notifDeliveryNote,
                  style: TextStyle(fontSize: 13, height: 1.45, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: accent,
      secondary: Icon(icon, color: accent),
      title: Text(title, style: const TextStyle(fontSize: 16)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
    );
  }

}

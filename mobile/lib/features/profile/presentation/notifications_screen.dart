import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/services/notification_service.dart';
import '../../glucose/presentation/glucose_providers.dart';
import '../../medications/presentation/medications_providers.dart';
import '../../medications/presentation/reminder_setup_sheet.dart';

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
                // A gentle, self-rearming nudge to log a glucose reading — the
                // patient's own control over the check-in prompt.
                _tile(
                  context,
                  accent: accent,
                  icon: Icons.monitor_heart_outlined,
                  title: 'Check-in reminders',
                  subtitle: 'A gentle nudge if you go quiet',
                  value: prefs.checkInReminders,
                  onChanged: (v) {
                    controller.setCheckInReminders(v);
                    if (v) {
                      syncCheckInReminder(ref).catchError((_) {});
                    } else {
                      NotificationService.instance.cancelCheckInReminder();
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
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                // Not a toggle — opens the reliability setup (battery exemption +
                // permissions) so a patient can (re)fix silenced dose alarms.
                ListTile(
                  leading: Icon(Icons.alarm_on_rounded, color: accent),
                  title: const Text('Reminder reliability', style: TextStyle(fontSize: 16)),
                  subtitle: const Text('Keep dose alarms firing when the phone sleeps', style: TextStyle(fontSize: 14)),
                  trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  onTap: () => showReminderSetupSheet(context, ref),
                  contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
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
                  style: TextStyle(fontSize: 14, height: 1.45, color: scheme.onSurfaceVariant),
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
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 14)),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
    );
  }

}

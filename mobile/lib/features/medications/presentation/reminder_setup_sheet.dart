import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/services/reminder_reliability.dart';
import 'medications_providers.dart';

/// Shows the reliability prompt at most once (unless reopened from settings),
/// and only when there's actually something to fix — so it never nags.
Future<void> maybePromptReminderSetup(BuildContext context, WidgetRef ref) async {
  final prefs = ref.read(appPreferencesProvider);
  if (prefs.reminderSetupDone || !prefs.medicationReminders) return;

  // Already exempt from battery optimization → nothing worth interrupting for;
  // quietly mark it done so we don't check every launch.
  final exempt = await ReminderReliability.isIgnoringBatteryOptimizations();
  if (exempt) {
    await ref.read(appPreferencesProvider.notifier).setReminderSetupDone(true);
    return;
  }
  if (!context.mounted) return;
  await showReminderSetupSheet(context, ref);
}

/// The "make reminders reliable" bottom sheet: one tap to grant notifications +
/// exact alarms and ask for a battery-optimization exemption, which together
/// keep dose alarms firing on aggressive OEMs.
Future<void> showReminderSetupSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _ReminderSetupSheet(),
  );
}

class _ReminderSetupSheet extends ConsumerStatefulWidget {
  const _ReminderSetupSheet();

  @override
  ConsumerState<_ReminderSetupSheet> createState() => _ReminderSetupSheetState();
}

class _ReminderSetupSheetState extends ConsumerState<_ReminderSetupSheet> {
  bool _working = false;

  Future<void> _enable() async {
    setState(() => _working = true);
    // Permissions first (notifications + exact alarms), then the OEM battery
    // exemption dialog, then re-arm so anything that couldn't schedule before
    // now does.
    await NotificationService.instance.ensureAlarmPermissions();
    await ReminderReliability.requestIgnoreBatteryOptimizations();
    await ref.read(appPreferencesProvider.notifier).setReminderSetupDone(true);
    await refreshAndScheduleMedicationReminders(ref);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _later() async {
    await ref.read(appPreferencesProvider.notifier).setReminderSetupDone(true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.alarm_on_rounded, color: accent, size: 26),
          ),
          const SizedBox(height: AppSpacing.md),
          const Text('Never miss a dose', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Some phones put apps to sleep and silence their alarms. One quick step keeps your medicine reminders firing on time, even when ClinQ is closed.',
            style: TextStyle(fontSize: 14, height: 1.4, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          _point(context, Icons.notifications_active_rounded, 'Show reminder alarms'),
          _point(context, Icons.schedule_rounded, 'Fire exactly on time'),
          _point(context, Icons.battery_saver_rounded, "Don't sleep the reminders"),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _working ? null : _enable,
              style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(50)),
              child: _working
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : const Text('Turn on reliable reminders', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: TextButton(
              onPressed: _working ? null : _later,
              child: Text('Maybe later', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _point(BuildContext context, IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 19, color: AppColors.accentOn(context)),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500))),
          Icon(Icons.check_circle_rounded, size: 18, color: scheme.outlineVariant),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/empty_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/medications_repository.dart';
import '../domain/medication.dart';
import 'medications_providers.dart';
import 'reminder_setup_sheet.dart';
import 'widgets/scan_prescription_sheet.dart';
import 'widgets/mark_dose_sheet.dart';
import 'widgets/medication_slot_tile.dart';

/// The patient's medicines: the windows their reminders fire in, what they are
/// currently prescribed, and today's outstanding doses.
class MedicationsScreen extends ConsumerStatefulWidget {
  const MedicationsScreen({super.key});

  @override
  ConsumerState<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends ConsumerState<MedicationsScreen>
    with WidgetsBindingObserver {
  Timer? _poll;

  /// Prescriptions and their times are the doctor's to change, not the
  /// patient's. Waiting for a pull-to-refresh meant a retimed dose kept showing
  /// the old hour — and, because the reminder scheduler is driven by this
  /// list, kept ringing at it too.
  static const _pollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollInterval, (_) => _refreshFromServer());
    // One-time: if reminders are on but the OS could sleep them, offer the
    // reliability fix. Post-frame so a sheet has a mounted context to open in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybePromptReminderSetup(context, ref);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshFromServer();
  }

  void _refreshFromServer() {
    if (mounted) _refreshAll(ref);
  }

  void _refreshAll(WidgetRef ref) {
    // Reloads everything a new medicine affects. Invalidating the list also
    // re-fires the reminder scheduler via the listener in build().
    ref.invalidate(todayScheduleProvider);
    ref.invalidate(medicationAdherenceProvider);
    ref.invalidate(medicationsListProvider);
  }

  /// Patients add medicines by scanning Dr.'s prescription only — typing them
  /// in is the doctor's side (the prescription form). This keeps the patient's
  /// medicine list faithful to what was actually prescribed.
  Future<void> _onScan(BuildContext context, WidgetRef ref) async {
    final added = await showScanPrescriptionSheet(context);
    if (added == true) _refreshAll(ref);
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    TodaySchedule schedule,
    MedicationScheduleSlot slot,
  ) async {
    final result = await showMarkDoseSheet(context, slot.name);
    if (result == null) return;

    final datePart = schedule.date.isNotEmpty
        ? schedule.date
        : DateTime.now().toIso8601String().substring(0, 10);
    final scheduledFor = DateTime.tryParse('${datePart}T${slot.time}:00') ?? DateTime.now();

    await ref
        .read(medicationsRepositoryProvider)
        .logDose(
          medicationId: slot.medicationId,
          scheduledFor: scheduledFor,
          status: result.status,
          skipReason: result.skipReason,
        );
    ref.invalidate(todayScheduleProvider);
    ref.invalidate(medicationAdherenceProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final medsAsyncRaw = ref.watch(medicationsListProvider);
    // Hold the last list while a background poll is in flight, or the screen
    // would drop to a spinner every thirty seconds.
    final medsLoaded = medsAsyncRaw.valueOrNull;
    final medsAsync = medsLoaded != null ? AsyncData<List<Medication>>(medsLoaded) : medsAsyncRaw;
    final scheduleAsync = ref.watch(todayScheduleProvider);
    final meals = ref.watch(mealTimesProvider).valueOrNull;

    // Keep on-device reminders in step with the live medication list: whenever
    // it (re)loads — after a scan, a manual add, or a doctor's prescription —
    // the daily reminders are rebuilt.
    ref.listen<AsyncValue<List<Medication>>>(medicationsListProvider, (_, next) {
      if (ref.read(appPreferencesProvider).medicationReminders) {
        next.whenData(
          (meds) => syncMedicationReminders(meds, today: ref.read(todayScheduleProvider).valueOrNull),
        );
      }
    });

    // Re-arm when today's statuses change too — so marking a dose taken cancels
    // today's alarm for that slot (the refetched schedule shows it taken, and
    // the rebuild leaves it out) instead of nagging for a dose already taken.
    ref.listen<AsyncValue<TodaySchedule>>(todayScheduleProvider, (_, next) {
      if (ref.read(appPreferencesProvider).medicationReminders) {
        next.whenData(
          (today) => syncMedicationReminders(
            ref.read(medicationsListProvider).valueOrNull ?? const [],
            today: today,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: scheme.surface,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onScan(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text(
          'Scan Prescription',
          style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _BrandHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  _refreshAll(ref);
                  ref.invalidate(mealTimesProvider);
                },
                child: medsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => ListView(
                    children: [
                      SizedBox(
                        height: 400,
                        child: ErrorView(
                          error: error,
                          onRetry: () => ref.invalidate(medicationsListProvider),
                        ),
                      ),
                    ],
                  ),
                  data: (meds) {
                    final active = meds.where((m) => m.isActive).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        110,
                      ),
                      children: [
                        const Text(
                          'Medications',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Manage your current prescriptions and daily schedule.',
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.4,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        const _MicroLabel('Reminder windows'),
                        const SizedBox(height: AppSpacing.sm),
                        _ReminderWindows(
                          meals: meals,
                          onTap: () => context.push('/medications/reminders'),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        const _MicroLabel('Active prescriptions'),
                        const SizedBox(height: AppSpacing.sm),
                        if (active.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.lg),
                            child: EmptyView(
                              icon: Icons.medication_outlined,
                              title: l10n.medsEmptyTitle,
                              body: l10n.medsEmptyBody,
                            ),
                          )
                        else
                          for (final med in active)
                            _PrescriptionCard(medication: med, meals: meals),

                        // Kept below the design's content rather than dropped:
                        // ticking a dose is what produces the adherence figure
                        // the doctor sees, and there is nowhere else to do it.
                        scheduleAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                          data: (schedule) => schedule.slots.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: AppSpacing.lg),
                                    _MicroLabel(l10n.medsTodaySchedule),
                                    const SizedBox(height: AppSpacing.sm),
                                    for (final slot in schedule.slots)
                                      MedicationSlotTile(
                                        slot: slot,
                                        onTap: () => _handleTap(context, ref, schedule, slot),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/brand/logo_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) =>
                Icon(Icons.medication_rounded, size: 26, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 10),
          Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/profile/notifications'),
            icon: Icon(Icons.notifications_none_rounded, size: 26, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _MicroLabel extends StatelessWidget {
  const _MicroLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

// ---- Reminder windows -----------------------------------------------------

class _ReminderWindows extends StatelessWidget {
  const _ReminderWindows({required this.meals, required this.onTap});

  final ({String breakfast, String lunch, String dinner})? meals;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final windows = <({IconData icon, String label, String time})>[
      (icon: Icons.wb_twilight_rounded, label: 'Breakfast', time: meals?.breakfast ?? '—'),
      (icon: Icons.wb_sunny_outlined, label: 'Lunch', time: meals?.lunch ?? '—'),
      (icon: Icons.nightlight_round, label: 'Dinner', time: meals?.dinner ?? '—'),
    ];

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < windows.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: _WindowCard(window: windows[i], onTap: onTap)),
          ],
        ],
      ),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.window, required this.onTap});

  final ({IconData icon, String label, String time}) window;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Column(
            children: [
              Icon(window.icon, size: 24, color: AppColors.accentOn(context)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                window.label,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(window.time, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Prescription card ----------------------------------------------------

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.medication, required this.meals});

  final Medication medication;
  final ({String breakfast, String lunch, String dinner})? meals;

  /// Splits "500 mg" into the number and its unit, so the amount can carry the
  /// weight and the unit sit quietly beside it.
  static (String, String) _splitStrength(String raw) {
    final match = RegExp(r'^\s*([\d.]+)\s*(.*)$').firstMatch(raw);
    if (match == null) return (raw, '');
    return (match.group(1) ?? raw, (match.group(2) ?? '').trim());
  }

  /// Which meal window a dose time falls closest to. Uses the patient's own
  /// meal times, so "1x Dinner" means their dinner, not a generic evening.
  String _windowFor(String time) {
    int minutes(String hhmm) {
      final parts = hhmm.split(':');
      if (parts.length != 2) return -1;
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }

    final t = minutes(time);
    if (t < 0 || meals == null) return '';

    final windows = <String, int>{
      'Breakfast': minutes(meals!.breakfast),
      'Lunch': minutes(meals!.lunch),
      'Dinner': minutes(meals!.dinner),
    };

    var best = '';
    var bestDelta = 1 << 30;
    windows.forEach((label, m) {
      final delta = (t - m).abs();
      if (m >= 0 && delta < bestDelta) {
        bestDelta = delta;
        best = label;
      }
    });
    return best;
  }

  ({IconData icon, String label}) _schedule() {
    final times = medication.schedule.map((s) => s.time).where((t) => t.isNotEmpty).toList();
    if (times.isEmpty) return (icon: Icons.schedule_rounded, label: 'As needed');

    final windows = times.map(_windowFor).where((w) => w.isNotEmpty).toList();

    if (times.length == 1) {
      final w = windows.isNotEmpty ? windows.first : times.first;
      return (
        icon: switch (w) {
          'Breakfast' => Icons.wb_twilight_rounded,
          'Lunch' => Icons.wb_sunny_outlined,
          'Dinner' => Icons.nightlight_round,
          _ => Icons.schedule_rounded,
        },
        label: '1x $w',
      );
    }

    final initials = windows.map((w) => w[0]).join('/');
    return (
      icon: Icons.autorenew_rounded,
      label: initials.isEmpty ? '${times.length}x Daily' : '${times.length}x Daily ($initials)',
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (amount, unit) = _splitStrength(medication.strength);
    final schedule = _schedule();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      medication.name,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2),
                    ),
                    // The doctor's own note about this medicine. No invented
                    // "what it's for" line: the record does not hold one, and a
                    // guessed indication is a clinical claim.
                    if (medication.instructions?.isNotEmpty == true) ...[
                      const SizedBox(height: 3),
                      Text(
                        medication.instructions!,
                        style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentSoftOn(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'ACTIVE',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppColors.accentOn(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.7)),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (amount.isNotEmpty)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        amount,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accentOn(context),
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(unit, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                )
              else
                const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(schedule.icon, size: 18, color: scheme.onSurface),
                    const SizedBox(width: 8),
                    Text(
                      schedule.label,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

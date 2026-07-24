import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/empty_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/medications_repository.dart';
import '../domain/medication.dart';
import 'medications_providers.dart';
import 'widgets/adherence_ring_card.dart';
import 'widgets/mark_dose_sheet.dart';
import 'widgets/medication_slot_tile.dart';

/// The "Medications" tab of the Track screen.
class MedicationsScreen extends ConsumerWidget {
  const MedicationsScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheduleAsync = ref.watch(todayScheduleProvider);
    final adherenceAsync = ref.watch(medicationAdherenceProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayScheduleProvider);
        ref.invalidate(medicationAdherenceProvider);
        await Future.wait([
          ref.read(todayScheduleProvider.future),
          ref.read(medicationAdherenceProvider.future),
        ]);
      },
      child: scheduleAsync.when(
        loading: () => ListView(
          children: const [
            SizedBox(height: 300, child: Center(child: CircularProgressIndicator())),
          ],
        ),
        error: (error, _) => ListView(
          children: [
            SizedBox(
              height: 400,
              child: ErrorView(error: error, onRetry: () => ref.invalidate(todayScheduleProvider)),
            ),
          ],
        ),
        data: (schedule) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xxl,
            ),
            children: [
              adherenceAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (adherence) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: AdherenceRingCard(adherence: adherence),
                ),
              ),
              Text(l10n.medsTodaySchedule, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (schedule.slots.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyView(
                    icon: Icons.medication_outlined,
                    title: l10n.medsEmptyTitle,
                    body: l10n.medsEmptyBody,
                  ),
                )
              else
                for (final slot in schedule.slots)
                  MedicationSlotTile(
                    slot: slot,
                    onTap: () => _handleTap(context, ref, schedule, slot),
                  ),
            ],
          );
        },
      ),
    );
  }
}

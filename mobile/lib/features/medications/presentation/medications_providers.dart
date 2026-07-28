import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/services/notification_service.dart';
import '../data/medications_repository.dart';
import '../domain/medication.dart';

final FutureProvider<TodaySchedule> todayScheduleProvider = FutureProvider<TodaySchedule>(
  (ref) => ref.watch(medicationsRepositoryProvider).getTodaySchedule(),
);

final FutureProvider<MedicationAdherence> medicationAdherenceProvider =
    FutureProvider<MedicationAdherence>(
      (ref) => ref.watch(medicationsRepositoryProvider).getAdherence(days: 30),
    );

/// The patient's medications. Fetched from the real API and reused both to list
/// medicines and to build the reminder schedule.
final FutureProvider<List<Medication>> medicationsListProvider = FutureProvider<List<Medication>>(
  (ref) => ref.watch(medicationsRepositoryProvider).getMedications(),
);

/// Flattens active medications into per-dose reminders and (re)schedules them on
/// the device, so a "time to take …" alert fires at each dose time even with the
/// app closed. Idempotent — the previous set is cancelled first. Call after a
/// fetch, after adding/stopping a medicine, on login, and on app resume.
Future<void> syncMedicationReminders(List<Medication> meds) async {
  final now = DateTime.now();
  final reminders = <MedReminder>[];
  for (final m in meds) {
    if (!m.isActive) continue;
    if (m.endDate != null && m.endDate!.isBefore(now)) continue;
    for (final s in m.schedule) {
      if (s.time.isEmpty) continue;
      reminders.add(
        MedReminder(
          medId: m.id,
          name: m.name,
          time: s.time,
          dose: m.dose.isNotEmpty ? m.dose : null,
          relationToMeal: s.relationToMeal,
        ),
      );
    }
  }
  await NotificationService.instance.scheduleMedicationReminders(reminders);
}

/// Fetches the patient's medications from the API and schedules their reminders.
/// The single call to make on login / app resume to bring reminders in sync with
/// whatever the doctor or patient has since prescribed.
Future<void> refreshAndScheduleMedicationReminders(WidgetRef ref) async {
  final meds = await ref.read(medicationsRepositoryProvider).getMedications();
  await syncMedicationReminders(meds);
}

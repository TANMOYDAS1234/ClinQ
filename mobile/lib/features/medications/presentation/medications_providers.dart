import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/core_providers.dart';
import '../../../shared/services/notification_service.dart';
import '../data/medications_repository.dart';
import '../domain/medication.dart';

/// The patient's own meal times, which every "after breakfast" reminder is
/// anchored to. Shown on the Medicines tab so the schedule below it reads in
/// the patient's own day rather than in abstract clock times.
final mealTimesProvider = FutureProvider.autoDispose<({String breakfast, String lunch, String dinner})>(
  (ref) async {
    final json = await ref.read(apiClientProvider).getJson('/auth/me');
    final profile = json['profile'] as Map<String, dynamic>? ?? const {};
    final meals = profile['mealTimes'] as Map<String, dynamic>? ?? const {};
    return (
      breakfast: meals['breakfast']?.toString() ?? '08:00',
      lunch: meals['lunch']?.toString() ?? '13:30',
      dinner: meals['dinner']?.toString() ?? '20:30',
    );
  },
);

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

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

/// The patient's dose history over [days] days (newest first) — the medicine-
/// taking history screen. Family so the range toggle re-fetches.
final doseHistoryProvider = FutureProvider.autoDispose.family<List<DoseHistoryEntry>, int>(
  (ref, days) => ref.watch(medicationsRepositoryProvider).getDoseHistory(days: days),
);

/// Expands active medications into their DAILY-REPEATING dose reminders — one
/// alarm per (medicine, slot time), which the OS then fires every day at that
/// time (see NotificationService: matchDateTimeComponents + exactAllowWhileIdle).
///
/// This is deliberately a daily repeat rather than a rolling window of one-shots:
/// the one-shot scheme silently stopped firing when the app wasn't reopened
/// overnight, which is exactly why a morning dose stopped alarming. A daily
/// repeat survives reboot and needs no re-arming.
///
/// PRN/Stat carry no reminders. Every-other-day / day-of-week nuances aren't
/// expressible as a plain daily repeat, so they fire daily — an occasional extra
/// reminder (safe) rather than a missed morning one. [today] is accepted for
/// call-site compatibility but no longer used.
List<ScheduledDose> buildUpcomingDoses(List<Medication> meds, {TodaySchedule? today}) {
  final now = DateTime.now();
  final doses = <ScheduledDose>[];
  final seen = <int>{};
  for (final m in meds) {
    if (!m.isActive || m.asNeeded || m.stat) continue;
    if (m.endDate != null && _dateOnly(m.endDate!).isBefore(_dateOnly(now))) continue;
    for (final s in m.schedule) {
      if (s.time.isEmpty) continue;
      final parts = s.time.split(':');
      if (parts.length != 2) continue;
      final hh = int.tryParse(parts[0]);
      final mm = int.tryParse(parts[1]);
      if (hh == null || mm == null || hh > 23 || mm > 59) continue;
      final id = medDailyReminderId(m.id, s.time);
      if (!seen.add(id)) continue; // one alarm per distinct slot time
      doses.add(
        ScheduledDose(
          id: id,
          medId: m.id,
          name: m.name,
          when: DateTime(now.year, now.month, now.day, hh, mm),
          dose: m.dose.isNotEmpty ? m.dose : null,
          relationToMeal: s.relationToMeal,
        ),
      );
    }
  }
  return doses;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// (Re)builds and arms the device reminders from [meds] and today's [today]
/// statuses. Returns how many alarms armed.
Future<int> syncMedicationReminders(List<Medication> meds, {TodaySchedule? today}) {
  return NotificationService.instance.scheduleMedicationReminders(buildUpcomingDoses(meds, today: today));
}

/// The single robust entry point — call on login, app resume, a schedule change,
/// and after marking a dose. Pulls the medications AND today's statuses, then
/// arms, retrying with backoff: at cold start the token or network is often not
/// ready on the first try, and silently swallowing that failure is exactly what
/// left patients un-reminded.
Future<void> refreshAndScheduleMedicationReminders(WidgetRef ref) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final repo = ref.read(medicationsRepositoryProvider);
      final meds = await repo.getMedications();
      TodaySchedule? today;
      try {
        today = await repo.getTodaySchedule();
      } catch (_) {
        // Non-fatal: without today's statuses we just don't skip taken slots.
      }
      final doses = buildUpcomingDoses(meds, today: today);
      final armed = await NotificationService.instance.scheduleMedicationReminders(doses);
      if (doses.isEmpty || armed > 0) return; // nothing to do, or it stuck
    } catch (_) {
      // fall through to retry
    }
    await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
  }
}

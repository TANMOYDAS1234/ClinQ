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

/// Rolling window (in days) of concrete dose alarms armed at once. Long enough
/// to bridge a normal gap between app opens; the server push (Tier 3) covers
/// longer silences, and every open re-extends the window.
const int _reminderWindowDays = 5;

/// Expands active medications into concrete upcoming dose alarms over the window,
/// skipping any slot the patient has ALREADY handled today (taken or skipped) so
/// a taken dose never nags and re-timing never re-fires it. [today] carries
/// today's per-slot status; without it, the today filter is simply skipped.
List<ScheduledDose> buildUpcomingDoses(List<Medication> meds, {TodaySchedule? today}) {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day);

  final handledToday = <String>{};
  for (final s in today?.slots ?? const <MedicationScheduleSlot>[]) {
    if (s.status == 'taken' || s.status == 'skipped') handledToday.add('${s.medicationId}@${s.time}');
  }

  final doses = <ScheduledDose>[];
  for (var d = 0; d < _reminderWindowDays; d++) {
    final day = midnight.add(Duration(days: d));
    for (final m in meds) {
      if (!m.isActive) continue;
      if (m.startDate != null && day.isBefore(_dateOnly(m.startDate!))) continue;
      if (m.endDate != null && day.isAfter(_dateOnly(m.endDate!))) continue;
      if (!_activeOnWeekday(m, day)) continue;
      for (final s in m.schedule) {
        if (s.time.isEmpty) continue;
        final parts = s.time.split(':');
        if (parts.length != 2) continue;
        final hh = int.tryParse(parts[0]);
        final mm = int.tryParse(parts[1]);
        if (hh == null || mm == null || hh > 23 || mm > 59) continue;
        final when = DateTime(day.year, day.month, day.day, hh, mm);
        if (when.isBefore(now)) continue; // dose time already passed
        if (d == 0 && handledToday.contains('${m.id}@${s.time}')) continue; // taken-aware
        doses.add(
          ScheduledDose(
            id: medReminderNotificationId(m.id, s.time, day),
            medId: m.id,
            name: m.name,
            when: when,
            dose: m.dose.isNotEmpty ? m.dose : null,
            relationToMeal: s.relationToMeal,
          ),
        );
      }
    }
  }
  return doses;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool _activeOnWeekday(Medication m, DateTime day) {
  if (m.daysOfWeek.isEmpty) return true;
  // Backend stores 0=Sun..6=Sat; Dart weekday is Mon=1..Sun=7, so % 7 maps back.
  final backendDow = day.weekday % 7;
  return m.daysOfWeek.contains(backendDow.toString());
}

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

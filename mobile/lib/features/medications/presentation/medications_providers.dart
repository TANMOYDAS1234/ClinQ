import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/medications_repository.dart';
import '../domain/medication.dart';

final FutureProvider<TodaySchedule> todayScheduleProvider = FutureProvider<TodaySchedule>(
  (ref) => ref.watch(medicationsRepositoryProvider).getTodaySchedule(),
);

final FutureProvider<MedicationAdherence> medicationAdherenceProvider =
    FutureProvider<MedicationAdherence>(
      (ref) => ref.watch(medicationsRepositoryProvider).getAdherence(days: 30),
    );

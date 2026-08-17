import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../foodlog/domain/food_log.dart';
import '../data/dietician_repository.dart';
import '../domain/diet_models.dart';

/// The dietician's day at a glance: counts, reviews due, plans not yet sent,
/// and the latest meals their patients logged.
final dietDashboardProvider = FutureProvider.autoDispose<DietDashboard>(
  (ref) => ref.watch(dieticianRepositoryProvider).dashboard(),
);

/// One patient's diet plan. Null until a dietician writes one.
final dietPlanProvider = FutureProvider.autoDispose.family<DietPlan?, String>(
  (ref, id) => ref.watch(dieticianRepositoryProvider).dietPlan(id),
);

/// The dietician's assigned-patient worklist.
final dietPatientsProvider = FutureProvider.autoDispose<List<DietPatient>>(
  (ref) => ref.watch(dieticianRepositoryProvider).patients(),
);

/// One patient's nutrition view (medical status + the doctor's medicine list).
final dietOverviewProvider =
    FutureProvider.autoDispose.family<DietPatientOverview, String>(
  (ref, id) => ref.watch(dieticianRepositoryProvider).overview(id),
);

/// The patient's care thread, as the dietician sees it.
final dietThreadProvider =
    FutureProvider.autoDispose.family<List<DietMessage>, String>(
  (ref, id) => ref.watch(dieticianRepositoryProvider).thread(id),
);

/// The patient's food log for the dietician to review.
final dietFoodLogProvider =
    FutureProvider.autoDispose.family<List<FoodLogEntry>, String>(
  (ref, id) => ref.watch(dieticianRepositoryProvider).foodLog(id),
);

/// Plans this patient has been taken off, newest first.
final dietPlanHistoryProvider =
    FutureProvider.autoDispose.family<List<DietPlanRevision>, String>(
  (ref, id) => ref.watch(dieticianRepositoryProvider).dietPlanHistory(id),
);

/// What is waiting for the dietician right now.
final dietNotificationsProvider = FutureProvider.autoDispose<DietNotifications>(
  (ref) => ref.watch(dieticianRepositoryProvider).notifications(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../foodlog/domain/food_log.dart';
import '../data/dietician_repository.dart';
import '../domain/diet_models.dart';

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

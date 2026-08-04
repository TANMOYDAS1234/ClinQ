import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/food_log_repository.dart';
import '../domain/food_log.dart';

/// The patient's own food-log entries, newest first.
final foodLogProvider = FutureProvider.autoDispose<List<FoodLogEntry>>(
  (ref) => ref.watch(foodLogRepositoryProvider).list(),
);

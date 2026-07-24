import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/paged.dart';
import '../data/glucose_repository.dart';
import '../domain/glucose_reading.dart';
import '../domain/glucose_trends.dart';

final FutureProvider<Paged<GlucoseReading>> glucoseReadingsProvider =
    FutureProvider<Paged<GlucoseReading>>(
      (ref) => ref.watch(glucoseRepositoryProvider).getReadings(limit: 30),
    );

final FutureProvider<GlucoseTrends> glucoseTrendsProvider = FutureProvider<GlucoseTrends>(
  (ref) => ref.watch(glucoseRepositoryProvider).getTrends(days: 30),
);

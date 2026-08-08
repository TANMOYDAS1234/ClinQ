import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/paged.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/services/notification_service.dart';
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

/// Re-arms the adaptive check-in reminder from the patient's most recent
/// reading. Honours the patient's toggle, so it is safe to call on app resume,
/// on login, and right after a reading is logged. [knownLast] skips the network
/// read when the caller already knows the latest reading time (e.g. it just
/// wrote one), which also avoids touching a provider from a widget being popped.
Future<void> syncCheckInReminder(WidgetRef ref, {DateTime? knownLast}) async {
  if (!ref.read(appPreferencesProvider).checkInReminders) {
    await NotificationService.instance.cancelCheckInReminder();
    return;
  }
  var last = knownLast;
  if (last == null) {
    try {
      final t = await ref.read(glucoseTrendsProvider.future);
      last = t.series.isNotEmpty ? t.series.last.at : null;
    } catch (_) {
      // No readings yet, or offline — fall through and arm a gentle first
      // nudge measured from now.
    }
  }
  await NotificationService.instance.scheduleCheckInReminder(lastReadingAt: last);
}

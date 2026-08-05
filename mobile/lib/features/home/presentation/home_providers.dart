import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/core_providers.dart';
import '../domain/care_summary.dart';

/// The patient's home screen, in one request. `/dashboard` already fans its
/// queries out in parallel server-side, so the screen arrives whole rather than
/// filling in section by section on a weak connection.
final careSummaryProvider = FutureProvider.autoDispose<CareSummary>((ref) async {
  // Mounted at /patients/:patientId/dashboard, and `me` resolves to the signed-
  // in patient. A bare /dashboard is a 404 — which is what "could not load your
  // care summary" was.
  final json = await ref.read(apiClientProvider).getJson('/patients/me/dashboard');
  return CareSummary.fromJson(json);
});

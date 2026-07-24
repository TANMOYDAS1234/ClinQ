import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/dashboard_data.dart';

/// `GET /patients/:patientId/dashboard` — the single call the home screen
/// makes (API_CONTRACT.md §10). The patient app always passes `me`.
class DashboardRepository {
  DashboardRepository(this._client);

  final ApiClient _client;

  Future<DashboardData> getDashboard() async {
    final json = await _client.getJson('/patients/me/dashboard');
    return DashboardData.fromJson(json);
  }
}

final Provider<DashboardRepository> dashboardRepositoryProvider = Provider<DashboardRepository>((
  ref,
) {
  return DashboardRepository(ref.watch(apiClientProvider));
});

final FutureProvider<DashboardData> dashboardProvider = FutureProvider<DashboardData>((ref) {
  return ref.watch(dashboardRepositoryProvider).getDashboard();
});

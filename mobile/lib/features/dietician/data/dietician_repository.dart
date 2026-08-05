import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../../foodlog/domain/food_log.dart';
import '../domain/diet_models.dart';

/// Talks to `/dietician/*` — the dietician panel API. A dietician only ever sees
/// the patients a doctor has assigned to them.
class DieticianRepository {
  DieticianRepository(this._client);

  final ApiClient _client;

  Future<DietDashboard> dashboard() async {
    return DietDashboard.fromJson(await _client.getJson('/dietician/dashboard'));
  }

  Future<DietPlan?> dietPlan(String patientId) async {
    final json = await _client.getJson('/dietician/patients/$patientId/diet');
    final plan = json['plan'];
    return plan is Map<String, dynamic> ? DietPlan.fromJson(plan) : null;
  }

  Future<DietPlan> saveDietPlan(String patientId, DietPlan plan) async {
    final json = await _client.putJson('/dietician/patients/$patientId/diet', body: plan.toJson());
    return DietPlan.fromJson(json['plan'] as Map<String, dynamic>? ?? const {});
  }

  /// Pushes the saved plan into the patient's care thread. Separate from saving
  /// on purpose: a dietician mid-edit should not be notifying the patient.
  Future<void> sendDietPlan(String patientId) async {
    await _client.postJson('/dietician/patients/$patientId/diet/send');
  }

  Future<List<DietPatient>> patients() async {
    final json = await _client.getJson('/dietician/patients');
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(DietPatient.fromJson).toList();
  }

  Future<DietPatientOverview> overview(String patientId) async {
    final json = await _client.getJson('/dietician/patients/$patientId/overview');
    return DietPatientOverview.fromJson(json);
  }

  Future<List<DietMessage>> thread(String patientId) async {
    final json = await _client.getJson('/dietician/patients/$patientId/thread');
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(DietMessage.fromJson).toList();
  }

  Future<List<FoodLogEntry>> foodLog(String patientId) async {
    final json = await _client.getJson('/dietician/patients/$patientId/food-log');
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(FoodLogEntry.fromJson).toList();
  }

  Future<void> sendMessage(String patientId, {String content = '', List<String> attachments = const []}) async {
    await _client.postJson(
      '/dietician/patients/$patientId/message',
      body: {'content': content, 'attachments': attachments},
    );
  }
}

final Provider<DieticianRepository> dieticianRepositoryProvider = Provider<DieticianRepository>((ref) {
  return DieticianRepository(ref.watch(apiClientProvider));
});

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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/medication.dart';

/// Talks to `/patients/me/medications*` (API_CONTRACT.md §4).
class MedicationsRepository {
  MedicationsRepository(this._client);

  final ApiClient _client;

  static const _base = '/patients/me/medications';

  Future<List<Medication>> getMedications() async {
    final json = await _client.getJson(_base);
    final items = json['items'] as List<dynamic>? ?? const [];
    return items.map((e) => Medication.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TodaySchedule> getTodaySchedule() async {
    final json = await _client.getJson('$_base/schedule/today');
    return TodaySchedule.fromJson(json);
  }

  Future<void> logDose({
    required String medicationId,
    required DateTime scheduledFor,
    required String status,
    num? unitsAdministered,
    String? injectionSite,
    String? skipReason,
  }) async {
    await _client.postJson(
      '$_base/$medicationId/log',
      body: {
        'scheduledFor': scheduledFor.toUtc().toIso8601String(),
        'status': status,
        if (unitsAdministered != null) 'unitsAdministered': unitsAdministered,
        if (injectionSite != null) 'injectionSite': injectionSite,
        if (skipReason != null) 'skipReason': skipReason,
      },
    );
  }

  Future<MedicationAdherence> getAdherence({int days = 30}) async {
    final json = await _client.getJson('$_base/adherence', query: {'days': days});
    return MedicationAdherence.fromJson(json);
  }
}

final Provider<MedicationsRepository> medicationsRepositoryProvider =
    Provider<MedicationsRepository>((ref) {
      return MedicationsRepository(ref.watch(apiClientProvider));
    });

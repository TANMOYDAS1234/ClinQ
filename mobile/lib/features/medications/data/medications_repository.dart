import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

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

  /// Adds a medicine to the patient's tracker. [schedule] is a list of
  /// `{time: "HH:mm", relationToMeal}` maps — the daily dose times the reminders
  /// are built from.
  Future<Medication> createMedication({
    required String name,
    required String form,
    String? strength,
    String? dose,
    required List<Map<String, String>> schedule,
    String? instructions,
  }) async {
    final json = await _client.postJson(
      _base,
      body: {
        'name': name,
        'form': form,
        if (strength != null && strength.isNotEmpty) 'strength': strength,
        if (dose != null && dose.isNotEmpty) 'dose': dose,
        'schedule': schedule,
        if (instructions != null && instructions.isNotEmpty) 'instructions': instructions,
      },
    );
    return Medication.fromJson(json['medication'] as Map<String, dynamic>);
  }

  /// Stops (soft-deletes) a medicine so it drops out of the schedule and its
  /// reminders stop.
  Future<void> stopMedication(String id) async {
    await _client.delete('$_base/$id');
  }

  /// Overrides a medicine's reminder times by hand. Each entry is
  /// `{time: "HH:mm", relationToMeal}`. The server marks it customised so a later
  /// meal-time change won't move it.
  Future<void> updateSchedule(String id, List<Map<String, String>> schedule) async {
    await _client.patchJson('$_base/$id', body: {'schedule': schedule});
  }

  /// Uploads a photo of a prescription; the server reads it and creates the
  /// medicines it finds. Returns what was created (or `readable: false` if the
  /// photo couldn't be read).
  Future<PrescriptionScanResult> scanPrescription({required String path, required String filename}) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
        contentType: MediaType.parse(_imageMime(filename)),
      ),
    });
    final json = await _client.postMultipart('$_base/scan', formData: formData);
    return PrescriptionScanResult.fromJson(json);
  }

  static String _imageMime(String filename) {
    switch (filename.toLowerCase().split('.').last) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
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

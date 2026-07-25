import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/paged.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/appointment.dart';

/// Talks to `/appointments`. Patients see and act on their own; clinicians see
/// the whole diary (the server scopes it by role).
class AppointmentRepository {
  AppointmentRepository(this._client);

  final ApiClient _client;

  Future<Paged<Appointment>> list({
    DateTime? from,
    DateTime? to,
    String? status,
    String? clinicId,
    String? patientId,
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson('/appointments', query: {
      'page': page,
      'limit': limit,
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (status != null) 'status': status,
      if (clinicId != null) 'clinicId': clinicId,
      if (patientId != null) 'patientId': patientId,
    });
    return Paged.fromJson(json, Appointment.fromJson);
  }

  /// Book a slot. [scheduledForIso] is the absolute ISO instant from the chosen
  /// [Slot]; the server re-validates it against the live schedule.
  Future<Appointment> book({
    required String clinicId,
    required String scheduledForIso,
    String mode = 'in_clinic',
    String? reason,
  }) async {
    final json = await _client.postJson('/appointments', body: {
      'clinicId': clinicId,
      'scheduledFor': scheduledForIso,
      'mode': mode,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  Future<Appointment> reschedule(String id, String scheduledForIso) async {
    final json = await _client.patchJson('/appointments/$id/reschedule', body: {'scheduledFor': scheduledForIso});
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  Future<Appointment> cancel(String id, {String? reason}) async {
    final json = await _client.patchJson('/appointments/$id/cancel', body: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }

  /// Clinician-only: advance the appointment's status (confirm, complete, …)
  /// and optionally attach consultation notes.
  Future<Appointment> setStatus(String id, String status, {String? consultationNotes}) async {
    final json = await _client.patchJson('/appointments/$id/status', body: {
      'status': status,
      if (consultationNotes != null && consultationNotes.isNotEmpty) 'consultationNotes': consultationNotes,
    });
    return Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
  }
}

final Provider<AppointmentRepository> appointmentRepositoryProvider = Provider<AppointmentRepository>((ref) {
  return AppointmentRepository(ref.watch(apiClientProvider));
});

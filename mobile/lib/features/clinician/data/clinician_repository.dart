import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/paged.dart';
import '../../../shared/providers/core_providers.dart';
import '../../chat/domain/chat_message.dart';
import '../../medications/domain/medication.dart';
import '../domain/appointment.dart';
import '../domain/chat_review.dart';
import '../domain/clinician_models.dart';
import '../domain/knowledge_chunk.dart';
import '../domain/patient_summary.dart';

/// Talks to `/doctor/*` — the clinician (doctor + staff) API: dashboard
/// overview, the patient directory, and clinical-alert triage.
class ClinicianRepository {
  ClinicianRepository(this._client);

  final ApiClient _client;

  Future<ClinicOverview> overview() async {
    final json = await _client.getJson('/doctor/overview');
    return ClinicOverview.fromJson(json);
  }

  Future<ClinicAnalytics> analytics({int days = 30}) async {
    final json = await _client.getJson('/doctor/analytics?days=$days');
    return ClinicAnalytics.fromJson(json);
  }

  Future<DoctorWorklist> worklist() async {
    return DoctorWorklist.fromJson(await _client.getJson('/doctor/worklist'));
  }

  /// Registers a walk-in patient from the clinic side — some patients are
  /// enrolled at the desk rather than downloading the app first.
  Future<void> createPatient({
    required String name,
    required String phone,
    required String password,
  }) async {
    await _client.postJson(
      '/doctor/patients',
      body: {'name': name, 'phone': phone, 'password': password},
    );
  }

  /// Today's clinic diary, earliest first. The API sorts newest-first and has no
  /// "today" filter of its own, so we pass an explicit day range and re-sort
  /// ascending for a top-to-bottom schedule.
  Future<List<Appointment>> appointmentsToday() async {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final json = await _client.getJson(
      '/appointments',
      query: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'limit': 200,
      },
    );
    return (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Appointment.fromJson)
        .toList()
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
  }

  /// The patient's own conversation, as the patient sees it.
  ///
  /// Reuses [ChatMessage] rather than a clinician-specific model on purpose:
  /// the doctor is reading the same thread, and a parallel type would let the
  /// two views drift apart.
  Future<
    ({
      String? patientName,
      String? patientPhone,
      String? patientAvatarUrl,
      List<ChatMessage> messages,
    })
  >
  patientThread(String patientId) async {
    final json = await _client.getJson(
      '/chat/patients/$patientId/thread',
      query: {'limit': 200},
    );
    final items =
        (json['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            // Sorted by createdAt, not seq: seq restarts per session, so it cannot
            // order a history that spans several.
            .map(ChatMessage.fromJson)
            .toList()
          ..sort((a, b) {
            final at = a.createdAt;
            final bt = b.createdAt;
            if (at == null || bt == null) return a.seq.compareTo(b.seq);
            return at.compareTo(bt);
          });

    final patient = json['patient'];
    return (
      patientName: patient is Map ? patient['name']?.toString() : null,
      // Carried so the clinician can call from inside the conversation.
      patientPhone: patient is Map ? patient['phone']?.toString() : null,
      patientAvatarUrl:
          patient is Map ? patient['avatarUrl']?.toString() : null,
      messages: items,
    );
  }

  /// Sends the clinician's own words into the patient's assistant thread.
  ///
  /// Not a separate inbox: the reply appears in the same conversation the
  /// patient is already reading, so the assistant's answers and the doctor's
  /// remain one exchange rather than two disconnected halves.
  Future<void> messagePatient({
    required String patientId,
    required String content,
    List<String> attachments = const [],
  }) async {
    await _client.postJson(
      '/chat/patients/$patientId/clinician-message',
      body: {
        'content': content,
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
    );
  }

  /// Writes a prescription for a patient. The server mirrors each medicine into
  /// the patient's tracker (with reminder times derived from its frequency), so
  /// the patient starts getting dose reminders automatically. [items] entries
  /// are `{name, strength?, dose?, frequency?, durationDays?, relationToMeal,
  /// instructions?}`.
  Future<void> createPrescription({
    required String patientId,
    required List<Map<String, dynamic>> items,
    List<String> diagnosis = const [],
    List<String> labTestsAdvised = const [],
    String? generalAdvice,
    DateTime? followUpOn,
  }) async {
    await _client.postJson(
      '/patients/$patientId/prescriptions',
      body: {
        'items': items,
        if (diagnosis.isNotEmpty) 'diagnosis': diagnosis,
        if (labTestsAdvised.isNotEmpty) 'labTestsAdvised': labTestsAdvised,
        if (generalAdvice != null && generalAdvice.isNotEmpty)
          'generalAdvice': generalAdvice,
        if (followUpOn != null) 'followUpOn': followUpOn.toIso8601String(),
      },
    );
  }

  /// The patient's past prescriptions/consultations, latest first.
  Future<List<PrescriptionSummary>> patientPrescriptions(String patientId) async {
    final json = await _client.getJson('/patients/$patientId/prescriptions?limit=20');
    final items = json['items'] as List? ?? const [];
    return items.whereType<Map<String, dynamic>>().map(PrescriptionSummary.fromJson).toList();
  }

  /// Dieticians the doctor can assign a patient to.
  Future<List<({String id, String name})>> dieticians() async {
    final json = await _client.getJson('/doctor/dieticians');
    final items = json['items'] as List? ?? const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (d) => (
            id: d['id']?.toString() ?? '',
            name: d['name']?.toString() ?? '',
          ),
        )
        .toList();
  }

  /// Creates a dietician account (the doctor onboarding one directly). Returns
  /// the new dietician so it can be assigned right away.
  Future<({String id, String name})> addDietician({
    required String name,
    required String phone,
    required String password,
  }) async {
    final json = await _client.postJson(
      '/doctor/dieticians',
      body: {'name': name, 'phone': phone, 'password': password},
    );
    return (
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  /// Assign the patient's dietician and food-log review cadence. A null
  /// [dieticianId] unassigns; a null [reviewIntervalDays] clears the cadence.
  Future<void> assignDietician(
    String patientId, {
    String? dieticianId,
    int? reviewIntervalDays,
  }) async {
    await _client.patchJson(
      '/doctor/patients/$patientId/dietician',
      body: {
        'dieticianId': dieticianId,
        'reviewIntervalDays': reviewIntervalDays,
      },
    );
  }

  Future<Paged<PatientListItem>> patients({
    String? riskBand,
    String? search,
    String sort = 'risk',
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson(
      '/doctor/patients',
      query: {
        'page': page,
        'limit': limit,
        'sort': sort,
        if (riskBand != null) 'riskBand': riskBand,
        if (search != null && search.isNotEmpty) 'search': search,
      },
    );
    return Paged.fromJson(json, PatientListItem.fromJson);
  }

  Future<PatientSummary> patientSummary(String id) async {
    final json = await _client.getJson('/doctor/patients/$id/summary');
    return PatientSummary.fromJson(json);
  }

  Future<Paged<ClinicalAlert>> alerts({
    String? status,
    String? severity,
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson(
      '/doctor/alerts',
      query: {
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (severity != null) 'severity': severity,
      },
    );
    return Paged.fromJson(json, ClinicalAlert.fromJson);
  }

  Future<ClinicalAlert> acknowledgeAlert(String id) async {
    final json = await _client.postJson('/doctor/alerts/$id/acknowledge');
    return ClinicalAlert.fromJson(json['alert'] as Map<String, dynamic>);
  }

  Future<ClinicalAlert> resolveAlert(String id, {String? notes}) async {
    final json = await _client.postJson(
      '/doctor/alerts/$id/resolve',
      body: {if (notes != null && notes.isNotEmpty) 'notes': notes},
    );
    return ClinicalAlert.fromJson(json['alert'] as Map<String, dynamic>);
  }

  // ---- The patient's current medicines ------------------------------------

  /// What this patient is already on.
  ///
  /// The prescribing form had no idea: the doctor wrote a new prescription
  /// without being shown the running list, which is how a drug gets duplicated
  /// or prescribed against something already there.
  Future<List<Medication>> patientMedications(String patientId) async {
    final json = await _client.getJson('/patients/$patientId/medications');
    final items = (json['items'] as List?) ?? (json['medications'] as List?) ?? const [];
    return items.whereType<Map<String, dynamic>>().map(Medication.fromJson).toList();
  }

  /// Stops a medicine. A soft stop on the server — it keeps `isActive: false`
  /// with an end date, so past doses and the adherence figure built from them
  /// stay interpretable.
  Future<void> stopMedication(String patientId, String medicationId) async {
    await _client.delete('/patients/$patientId/medications/$medicationId');
  }

  // ---- Chat review ------------------------------------------------------

  /// [kind] is `care` (assistant + doctor) or `nutrition` (the dietician's own
  /// thread); null returns both. Without it the Nutrition tab was the same
  /// query as All chats and simply showed everything.
  Future<Paged<ChatReviewSession>> chatReviewSessions({
    bool flagged = true,
    String? urgency,
    String? kind,
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson(
      '/doctor/chat-review',
      query: {
        'page': page,
        'limit': limit,
        'flagged': flagged,
        if (urgency != null) 'urgency': urgency,
        if (kind != null) 'kind': kind,
      },
    );
    return Paged.fromJson(json, ChatReviewSession.fromJson);
  }

  Future<ChatReviewDetail> chatReviewDetail(String sessionId) async {
    final json = await _client.getJson('/doctor/chat-review/$sessionId');
    return ChatReviewDetail.fromJson(json);
  }

  Future<void> markReviewed(String sessionId) async {
    await _client.postJson('/doctor/chat-review/$sessionId/reviewed');
  }

  // ---- Knowledge base ---------------------------------------------------

  Future<Paged<KnowledgeChunk>> knowledge({
    String? status,
    String? category,
    String? language,
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson(
      '/doctor/knowledge',
      query: {
        'page': page,
        'limit': limit,
        if (status != null) 'status': status,
        if (category != null) 'category': category,
        if (language != null) 'language': language,
      },
    );
    return Paged.fromJson(json, KnowledgeChunk.fromJson);
  }

  Future<KnowledgeChunk> createKnowledge(Map<String, dynamic> body) async {
    final json = await _client.postJson('/doctor/knowledge', body: body);
    return KnowledgeChunk.fromJson(json['chunk'] as Map<String, dynamic>);
  }

  Future<KnowledgeChunk> updateKnowledge(
    String id,
    Map<String, dynamic> body,
  ) async {
    final json = await _client.patchJson('/doctor/knowledge/$id', body: body);
    return KnowledgeChunk.fromJson(json['chunk'] as Map<String, dynamic>);
  }

  Future<KnowledgeChunk> approveKnowledge(String id) async {
    final json = await _client.postJson('/doctor/knowledge/$id/approve');
    return KnowledgeChunk.fromJson(json['chunk'] as Map<String, dynamic>);
  }

  Future<KnowledgeChunk> retireKnowledge(String id) async {
    final json = await _client.postJson('/doctor/knowledge/$id/retire');
    return KnowledgeChunk.fromJson(json['chunk'] as Map<String, dynamic>);
  }
}

final Provider<ClinicianRepository> clinicianRepositoryProvider =
    Provider<ClinicianRepository>((ref) {
      return ClinicianRepository(ref.watch(apiClientProvider));
    });

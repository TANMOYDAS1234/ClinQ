import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/paged.dart';
import '../../../shared/providers/core_providers.dart';
import '../../chat/domain/chat_message.dart';
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

  /// The patient's own conversation, as the patient sees it.
  ///
  /// Reuses [ChatMessage] rather than a clinician-specific model on purpose:
  /// the doctor is reading the same thread, and a parallel type would let the
  /// two views drift apart.
  Future<({String? patientName, List<ChatMessage> messages})> patientThread(String patientId) async {
    final json = await _client.getJson('/chat/patients/$patientId/thread', query: {'limit': 100});
    final items = (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));

    final patient = json['patient'];
    return (
      patientName: patient is Map ? patient['name']?.toString() : null,
      messages: items,
    );
  }

  /// Sends the clinician's own words into the patient's assistant thread.
  ///
  /// Not a separate inbox: the reply appears in the same conversation the
  /// patient is already reading, so the assistant's answers and the doctor's
  /// remain one exchange rather than two disconnected halves.
  Future<void> messagePatient({required String patientId, required String content}) async {
    await _client.postJson('/chat/patients/$patientId/clinician-message', body: {'content': content});
  }

  Future<Paged<PatientListItem>> patients({
    String? riskBand,
    String? search,
    String sort = 'risk',
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson('/doctor/patients', query: {
      'page': page,
      'limit': limit,
      'sort': sort,
      if (riskBand != null) 'riskBand': riskBand,
      if (search != null && search.isNotEmpty) 'search': search,
    });
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
    final json = await _client.getJson('/doctor/alerts', query: {
      'page': page,
      'limit': limit,
      if (status != null) 'status': status,
      if (severity != null) 'severity': severity,
    });
    return Paged.fromJson(json, ClinicalAlert.fromJson);
  }

  Future<ClinicalAlert> acknowledgeAlert(String id) async {
    final json = await _client.postJson('/doctor/alerts/$id/acknowledge');
    return ClinicalAlert.fromJson(json['alert'] as Map<String, dynamic>);
  }

  Future<ClinicalAlert> resolveAlert(String id, {String? notes}) async {
    final json = await _client.postJson('/doctor/alerts/$id/resolve', body: {
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    return ClinicalAlert.fromJson(json['alert'] as Map<String, dynamic>);
  }

  // ---- Chat review ------------------------------------------------------

  Future<Paged<ChatReviewSession>> chatReviewSessions({
    bool flagged = true,
    String? urgency,
    int page = 1,
    int limit = 50,
  }) async {
    final json = await _client.getJson('/doctor/chat-review', query: {
      'page': page,
      'limit': limit,
      'flagged': flagged,
      if (urgency != null) 'urgency': urgency,
    });
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
    final json = await _client.getJson('/doctor/knowledge', query: {
      'page': page,
      'limit': limit,
      if (status != null) 'status': status,
      if (category != null) 'category': category,
      if (language != null) 'language': language,
    });
    return Paged.fromJson(json, KnowledgeChunk.fromJson);
  }

  Future<KnowledgeChunk> createKnowledge(Map<String, dynamic> body) async {
    final json = await _client.postJson('/doctor/knowledge', body: body);
    return KnowledgeChunk.fromJson(json['chunk'] as Map<String, dynamic>);
  }

  Future<KnowledgeChunk> updateKnowledge(String id, Map<String, dynamic> body) async {
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

final Provider<ClinicianRepository> clinicianRepositoryProvider = Provider<ClinicianRepository>((ref) {
  return ClinicianRepository(ref.watch(apiClientProvider));
});

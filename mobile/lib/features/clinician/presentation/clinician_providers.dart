import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/paged.dart';
import '../data/clinician_repository.dart';
import '../domain/appointment.dart';
import '../domain/chat_review.dart';
import '../domain/clinician_models.dart';
import '../domain/knowledge_chunk.dart';
import '../domain/patient_summary.dart';

/// Dashboard headline numbers.
final overviewProvider = FutureProvider.autoDispose<ClinicOverview>((ref) {
  return ref.watch(clinicianRepositoryProvider).overview();
});

/// Today's clinic diary (kept for the appointments admin screen).
final appointmentsTodayProvider = FutureProvider.autoDispose<List<Appointment>>((ref) {
  return ref.watch(clinicianRepositoryProvider).appointmentsToday();
});

/// Patients for the dashboard's "Needs Attention" worklist. Pulled risk-first
/// from the directory; the dashboard ranks the ones actually needing action
/// (alerts, unread, abnormal glucose, high risk) on the client.
final attentionPatientsProvider = FutureProvider.autoDispose<List<PatientListItem>>((ref) async {
  final paged = await ref.watch(clinicianRepositoryProvider).patients(sort: 'risk', limit: 100);
  return paged.items;
});

typedef PatientsQuery = ({String? riskBand, String? search, String sort});

final patientsProvider =
    FutureProvider.autoDispose.family<Paged<PatientListItem>, PatientsQuery>((ref, q) {
  return ref.watch(clinicianRepositoryProvider).patients(
        riskBand: q.riskBand,
        search: q.search,
        sort: q.sort,
        limit: 100,
      );
});

final patientSummaryProvider =
    FutureProvider.autoDispose.family<PatientSummary, String>((ref, id) {
  return ref.watch(clinicianRepositoryProvider).patientSummary(id);
});

typedef AlertsQuery = ({String? status, String? severity});

final alertsProvider =
    FutureProvider.autoDispose.family<Paged<ClinicalAlert>, AlertsQuery>((ref, q) {
  return ref.watch(clinicianRepositoryProvider).alerts(
        status: q.status,
        severity: q.severity,
        limit: 100,
      );
});

// ---- Chat review --------------------------------------------------------

typedef ChatReviewQuery = ({bool flagged, String? urgency});

final chatReviewProvider =
    FutureProvider.autoDispose.family<Paged<ChatReviewSession>, ChatReviewQuery>((ref, q) {
  return ref.watch(clinicianRepositoryProvider).chatReviewSessions(
        flagged: q.flagged,
        urgency: q.urgency,
        limit: 100,
      );
});

final chatReviewDetailProvider =
    FutureProvider.autoDispose.family<ChatReviewDetail, String>((ref, sessionId) {
  return ref.watch(clinicianRepositoryProvider).chatReviewDetail(sessionId);
});

// ---- Knowledge base -----------------------------------------------------

typedef KnowledgeQuery = ({String? status, String? category, String? language});

final knowledgeProvider =
    FutureProvider.autoDispose.family<Paged<KnowledgeChunk>, KnowledgeQuery>((ref, q) {
  return ref.watch(clinicianRepositoryProvider).knowledge(
        status: q.status,
        category: q.category,
        language: q.language,
        limit: 100,
      );
});

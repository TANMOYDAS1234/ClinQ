/// A patient chat thread flagged for clinician review (`/doctor/chat-review`).
class ChatReviewSession {
  const ChatReviewSession({
    required this.id,
    required this.title,
    required this.highestUrgency,
    this.patientId,
    this.patientName,
    this.language,
    this.messageCount = 0,
    this.flaggedForReview = false,
    this.reviewedAt,
    this.lastMessageAt,
  });

  final String id;
  final String title;
  final String highestUrgency; // routine | advice | urgent | emergency
  final String? patientId;
  final String? patientName;
  final String? language;
  final int messageCount;
  final bool flaggedForReview;
  final DateTime? reviewedAt;
  final DateTime? lastMessageAt;

  factory ChatReviewSession.fromJson(Map<String, dynamic> j) => ChatReviewSession(
    id: j['id']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    highestUrgency: j['highestUrgency']?.toString() ?? 'routine',
    patientId: j['patientId']?.toString(),
    patientName: j['patientName']?.toString(),
    language: j['language']?.toString(),
    messageCount: (j['messageCount'] as num?)?.toInt() ?? 0,
    flaggedForReview: j['flaggedForReview'] == true,
    reviewedAt: DateTime.tryParse(j['reviewedAt']?.toString() ?? '')?.toLocal(),
    lastMessageAt: DateTime.tryParse(j['lastMessageAt']?.toString() ?? '')?.toLocal(),
  );
}

/// One message in a reviewed conversation, with the audit trail (triage rules,
/// grounding citations, fallback flag) the doctor needs to judge the answer.
class ChatReviewMessage {
  const ChatReviewMessage({
    required this.id,
    required this.seq,
    required this.role,
    required this.content,
    required this.urgency,
    this.matchedRules = const [],
    this.ruleDriven = false,
    this.citations = const [],
    this.isFallback = false,
    this.flaggedByPatient = false,
    this.modelVersion,
    this.latencyMs,
    this.createdAt,
  });

  final String id;
  final int seq;
  final String role; // user | assistant
  final String content;
  final String urgency;
  final List<String> matchedRules;
  final bool ruleDriven;
  final List<String> citations; // titles
  final bool isFallback;
  final bool flaggedByPatient;
  final String? modelVersion;
  final int? latencyMs;
  final DateTime? createdAt;

  bool get isUser => role == 'user';

  factory ChatReviewMessage.fromJson(Map<String, dynamic> j) => ChatReviewMessage(
    id: j['id']?.toString() ?? '',
    seq: (j['seq'] as num?)?.toInt() ?? 0,
    role: j['role']?.toString() ?? 'assistant',
    content: j['content']?.toString() ?? '',
    urgency: j['urgency']?.toString() ?? 'routine',
    matchedRules: (j['matchedRules'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    ruleDriven: j['ruleDriven'] == true,
    citations: (j['citations'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((c) => c['title']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList() ??
        const [],
    isFallback: j['isFallback'] == true,
    flaggedByPatient: j['flaggedByPatient'] == true,
    modelVersion: j['modelVersion']?.toString(),
    latencyMs: (j['latencyMs'] as num?)?.toInt(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
  );
}

class ChatReviewDetail {
  const ChatReviewDetail({required this.session, required this.messages});
  final ChatReviewSession session;
  final List<ChatReviewMessage> messages;

  factory ChatReviewDetail.fromJson(Map<String, dynamic> j) => ChatReviewDetail(
    session: ChatReviewSession.fromJson(j['session'] as Map<String, dynamic>? ?? const {}),
    messages: (j['messages'] as List?)?.whereType<Map<String, dynamic>>().map(ChatReviewMessage.fromJson).toList() ?? const [],
  );
}

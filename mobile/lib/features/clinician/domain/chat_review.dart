import '../../chat/domain/chat_message.dart';
import 'clinician_models.dart' show MessagePreview;

/// A patient chat thread flagged for clinician review (`/doctor/chat-review`).
class ChatReviewSession {
  const ChatReviewSession({
    required this.id,
    required this.title,
    required this.highestUrgency,
    this.patientId,
    this.patientName,
    this.avatarUrl,
    this.language,
    this.messageCount = 0,
    this.flaggedForReview = false,
    this.reviewedAt,
    this.lastMessageAt,
    this.lastMessage,
    this.unreadCount = 0,
    this.kind = 'care',
  });

  final String id;
  final String title;
  final String highestUrgency; // routine | advice | urgent | emergency
  final String? patientId;
  final String? patientName;

  /// The patient's profile photo, so the inbox row shows a face rather than an
  /// initial. Null when they have not set one.
  final String? avatarUrl;
  final String? language;
  final int messageCount;
  final bool flaggedForReview;
  final DateTime? reviewedAt;
  final DateTime? lastMessageAt;

  /// The newest turn in the thread — who spoke, what they said, and when — so
  /// the row reads like an inbox instead of a static title.
  final MessagePreview? lastMessage;

  /// Patient messages nobody at the clinic has opened in this conversation.
  final int unreadCount;

  /// `care` (assistant + doctor) or `nutrition` (the dietician's thread).
  final String kind;

  factory ChatReviewSession.fromJson(Map<String, dynamic> j) =>
      ChatReviewSession(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        highestUrgency: j['highestUrgency']?.toString() ?? 'routine',
        patientId: j['patientId']?.toString(),
        patientName: j['patientName']?.toString(),
        avatarUrl: j['avatarUrl']?.toString(),
        language: j['language']?.toString(),
        messageCount: (j['messageCount'] as num?)?.toInt() ?? 0,
        flaggedForReview: j['flaggedForReview'] == true,
        reviewedAt:
            DateTime.tryParse(j['reviewedAt']?.toString() ?? '')?.toLocal(),
        lastMessageAt:
            DateTime.tryParse(j['lastMessageAt']?.toString() ?? '')?.toLocal(),
        lastMessage: j['lastMessage'] is Map<String, dynamic>
            ? MessagePreview.fromJson(j['lastMessage'] as Map<String, dynamic>)
            : null,
        unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
        kind: j['kind']?.toString() ?? 'care',
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
    this.senderName,
    this.senderAvatarUrl,
    this.pinned = false,
    this.deletedForEveryone = false,
    this.replyToId,
    this.replyPreviewContent,
    this.imagePaths = const [],
    this.voiceNotes = const [],
    this.documents = const [],
  });

  /// Kept at the top of the thread (mirrors the patient/doctor bubbles).
  final bool pinned;

  /// Deleted for everyone by its author — rendered as a tombstone.
  final bool deletedForEveryone;

  /// The message this one answers, plus a server-sent preview of it, so a reply
  /// shows its quote even when the original is off-screen.
  final String? replyToId;
  final String? replyPreviewContent;

  /// Who wrote a `clinician` or `dietician` turn. Null on patient and
  /// assistant turns.
  final String? senderName;

  /// Their own photo, so a dietician's turn carries a face.
  final String? senderAvatarUrl;

  /// Photos on this turn, as relative `/uploads/:id/raw` paths.
  ///
  /// A food photo *is* the message. Reviewing the assistant's answer about a
  /// meal without seeing the meal is reviewing half the exchange.
  final List<String> imagePaths;
  final List<VoiceNote> voiceNotes;
  final List<DocumentAttachment> documents;

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

  /// A doctor or staff member who replied into this thread, not the assistant.
  bool get isClinician => role == 'clinician';

  factory ChatReviewMessage.fromJson(Map<String, dynamic> j) =>
      ChatReviewMessage(
        id: j['id']?.toString() ?? '',
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        role: j['role']?.toString() ?? 'assistant',
        content: j['content']?.toString() ?? '',
        urgency: j['urgency']?.toString() ?? 'routine',
        matchedRules:
            (j['matchedRules'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        ruleDriven: j['ruleDriven'] == true,
        citations:
            (j['citations'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map((c) => c['title']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList() ??
            const [],
        isFallback: j['isFallback'] == true,
        flaggedByPatient: j['flaggedByPatient'] == true,
        modelVersion: j['modelVersion']?.toString(),
        latencyMs: (j['latencyMs'] as num?)?.toInt(),
        createdAt:
            DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
        senderName: j['senderName']?.toString(),
        senderAvatarUrl: j['senderAvatarUrl']?.toString(),
        pinned: j['pinned'] == true,
        deletedForEveryone: j['deletedForEveryone'] == true,
        replyToId: j['replyToId']?.toString(),
        replyPreviewContent: j['replyPreview'] is Map
            ? (j['replyPreview'] as Map)['content']?.toString()
            : null,
        imagePaths:
            _attachments(j)
                .where(isImageAttachment)
                .map((a) => a['url']?.toString() ?? '')
                .where((s) => s.isNotEmpty)
                .toList(),
        voiceNotes:
            _attachments(j)
                .where(isAudioAttachment)
                .map(
                  (a) => VoiceNote(
                    url: a['url']?.toString() ?? '',
                    transcript: a['transcript']?.toString(),
                    mimeType: a['mimeType']?.toString(),
                  ),
                )
                .where((v) => v.url.isNotEmpty)
                .toList(),
        documents:
            _attachments(j)
                .where(isDocumentAttachment)
                .map(
                  (a) => DocumentAttachment(
                    url: a['url']?.toString() ?? '',
                    name: a['originalName']?.toString() ?? 'Document',
                    mimeType: a['mimeType']?.toString(),
                    sizeBytes: (a['sizeBytes'] as num?)?.toInt(),
                  ),
                )
                .where((d) => d.url.isNotEmpty)
                .toList(),
      );

  static List<Map<String, dynamic>> _attachments(Map<String, dynamic> j) =>
      (j['attachments'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
      const [];
}

class ChatReviewDetail {
  const ChatReviewDetail({required this.session, required this.messages});
  final ChatReviewSession session;
  final List<ChatReviewMessage> messages;

  factory ChatReviewDetail.fromJson(Map<String, dynamic> j) => ChatReviewDetail(
    session: ChatReviewSession.fromJson(
      j['session'] as Map<String, dynamic>? ?? const {},
    ),
    messages:
        (j['messages'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(ChatReviewMessage.fromJson)
            .toList() ??
        const [],
  );
}

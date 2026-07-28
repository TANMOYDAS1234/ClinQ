import 'citation.dart';
import 'triage.dart';

/// A single turn in a chat session. Matches the `userMessage`/`reply`
/// shape from `POST /chat/message` and the items returned by
/// `GET /chat/sessions/:id/messages` (API_CONTRACT.md §2).
///
/// [citations] and [triage] are NOT part of the message object itself in
/// the contract — they arrive as sibling fields on the `POST /chat/message`
/// response. This app attaches them to the freshly-created assistant
/// message client-side (see `ChatController`) so the emergency/urgent card
/// and citation chips can render immediately after sending. History
/// re-fetched via `GET /chat/sessions/:id/messages` will not have them, but
/// still carries `urgency` (a real per-message field), which is what
/// drives the emergency banner regardless of source.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.seq,
    required this.role,
    required this.content,
    required this.language,
    required this.urgency,
    this.isFallback,
    this.createdAt,
    this.citations,
    this.triage,
    this.senderName,
    this.pinned = false,
    this.replyToId,
    this.replyPreviewContent,
    this.seenByClinicAt,
    this.attachmentPaths = const [],
  });

  /// Kept at the top of the thread. A dosing instruction otherwise scrolls out
  /// of reach within a day.
  final bool pinned;

  /// The message this one answers, when the sender quoted an earlier turn.
  final String? replyToId;

  /// A text preview of the quoted turn, sent by the server so the reply's quote
  /// renders even when the original message is not loaded on this side.
  final String? replyPreviewContent;

  /// When the clinic first read this message. Shown to the patient as "Seen by
  /// the clinic" — chosen over a typing indicator, which would promise a reply
  /// within seconds that a clinician with a full list cannot keep.
  final DateTime? seenByClinicAt;

  final String id;
  final int seq;

  /// `user` | `assistant` | `clinician`.
  ///
  /// `clinician` is the doctor or staff speaking directly into this thread.
  /// There is no separate clinic inbox — the assistant answers what it safely
  /// can and refers the rest, and the clinician's reply lands here so the whole
  /// exchange stays one conversation.
  final String role;
  final String content;
  final String language;

  /// Who wrote a `clinician` turn, e.g. "Dr. Amit Kumar Dey". Null otherwise.
  final String? senderName;

  /// routine < advice < urgent < emergency.
  final String urgency;
  final bool? isFallback;
  final DateTime? createdAt;

  final List<Citation>? citations;
  final Triage? triage;

  /// Relative `/api/v1/uploads/:id/raw` paths of photos the patient attached.
  /// The full URL and auth header are assembled at render time.
  final List<String> attachmentPaths;

  bool get isUser => role == 'user';

  /// A real person from the clinic, not the assistant. Rendered distinctly so a
  /// patient is never unsure whether they are reading their doctor or an AI.
  bool get isClinician => role == 'clinician';

  bool get isEmergency => urgency == 'emergency';
  bool get isUrgent => urgency == 'urgent';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      role: json['role']?.toString() ?? 'assistant',
      content: json['content']?.toString() ?? '',
      language: json['language']?.toString() ?? 'en',
      urgency: json['urgency']?.toString() ?? 'routine',
      isFallback: json['isFallback'] as bool?,
      createdAt: json['createdAt'] == null ? null : DateTime.tryParse(json['createdAt'].toString()),
      senderName: json['senderName']?.toString(),
      pinned: json['pinned'] == true,
      replyToId: json['replyToId']?.toString(),
      replyPreviewContent: json['replyPreview'] is Map
          ? (json['replyPreview'] as Map)['content']?.toString()
          : null,
      seenByClinicAt: json['seenByClinicAt'] == null
          ? null
          : DateTime.tryParse(json['seenByClinicAt'].toString()),
      attachmentPaths: _parseAttachments(json['attachments']),
    );
  }

  /// Attachments arrive as `[{id, url}]`; keep the relative url.
  static List<String> _parseAttachments(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((a) => a is Map ? a['url']?.toString() : a?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Returns a copy with new [content] — used to grow a streaming reply as
  /// tokens arrive, keeping every other field.
  ChatMessage withContent(String content) => ChatMessage(
    id: id,
    seq: seq,
    role: role,
    content: content,
    language: language,
    urgency: urgency,
    isFallback: isFallback,
    createdAt: createdAt,
    citations: citations,
    triage: triage,
    senderName: senderName,
    pinned: pinned,
    replyToId: replyToId,
    replyPreviewContent: replyPreviewContent,
    seenByClinicAt: seenByClinicAt,
    attachmentPaths: attachmentPaths,
  );

  /// Returns a copy with [pinned] flipped, so the thread reorders immediately
  /// instead of waiting for the next poll to confirm it.
  ChatMessage withPinned(bool value) => ChatMessage(
    id: id,
    seq: seq,
    role: role,
    content: content,
    language: language,
    urgency: urgency,
    isFallback: isFallback,
    createdAt: createdAt,
    citations: citations,
    triage: triage,
    senderName: senderName,
    pinned: value,
    replyToId: replyToId,
    replyPreviewContent: replyPreviewContent,
    seenByClinicAt: seenByClinicAt,
    attachmentPaths: attachmentPaths,
  );

  ChatMessage copyWith({List<Citation>? citations, Triage? triage}) {
    return ChatMessage(
      id: id,
      seq: seq,
      role: role,
      content: content,
      language: language,
      urgency: urgency,
      isFallback: isFallback,
      createdAt: createdAt,
      citations: citations ?? this.citations,
      triage: triage ?? this.triage,
      senderName: senderName,
      attachmentPaths: attachmentPaths,
    );
  }
}

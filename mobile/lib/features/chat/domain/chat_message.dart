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
    this.attachmentPaths = const [],
  });

  final String id;
  final int seq;

  /// `user` | `assistant`.
  final String role;
  final String content;
  final String language;

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
      attachmentPaths: attachmentPaths,
    );
  }
}

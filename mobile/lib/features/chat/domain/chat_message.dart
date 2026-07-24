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
    );
  }

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
    );
  }
}

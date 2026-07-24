/// The contract documents `GET /chat/sessions` as returning "paged
/// `ChatSession`" without enumerating its fields. This mapping is a
/// best-effort, defensive parse of the fields a session list plausibly
/// carries (title/preview/last-activity/message-count), trying a couple of
/// common key spellings and falling back gracefully so an unexpected
/// backend shape never crashes the session drawer — see mobile/README.md
/// "Contract ambiguities".
class ChatSession {
  const ChatSession({
    required this.id,
    this.title,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.createdAt,
    this.messageCount,
    this.isArchived = false,
    this.language,
  });

  final String id;
  final String? title;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final int? messageCount;
  final bool isArchived;
  final String? language;

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString(),
      lastMessagePreview:
          (json['lastMessagePreview'] ?? json['preview'] ?? json['lastMessage'])?.toString(),
      lastMessageAt: _date(json['lastMessageAt'] ?? json['updatedAt']),
      createdAt: _date(json['createdAt'] ?? json['startedAt']),
      messageCount: (json['messageCount'] as num?)?.toInt(),
      isArchived: json['isArchived'] as bool? ?? json['archived'] as bool? ?? false,
      language: json['language']?.toString(),
    );
  }

  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}

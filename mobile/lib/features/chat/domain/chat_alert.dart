/// `alert` object from `POST /chat/message` (API_CONTRACT.md §2):
/// `{ id, severity, type, title }`, or `null` when urgency is
/// `routine`/`advice`.
class ChatAlert {
  const ChatAlert({required this.id, required this.severity, required this.type, required this.title});

  final String id;
  final String severity;
  final String type;
  final String title;

  factory ChatAlert.fromJson(Map<String, dynamic> json) {
    return ChatAlert(
      id: json['id']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'routine',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
    );
  }
}

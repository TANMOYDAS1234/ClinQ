/// One human message between a patient and the clinic (not the AI assistant).
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderRole,
    required this.content,
    this.senderName,
    this.createdAt,
  });

  final String id;

  /// 'patient' | 'doctor' | 'staff'
  final String senderRole;
  final String content;
  final String? senderName;
  final DateTime? createdAt;

  bool get fromPatient => senderRole == 'patient';

  factory DirectMessage.fromJson(Map<String, dynamic> j) => DirectMessage(
    id: j['id']?.toString() ?? '',
    senderRole: j['senderRole']?.toString() ?? 'patient',
    content: j['content']?.toString() ?? '',
    senderName: j['senderName']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
  );
}

/// A row in the clinician's message inbox — one conversation per patient.
class MessageThread {
  const MessageThread({
    required this.patientId,
    this.patientName,
    this.patientPhone,
    this.lastMessage,
    this.lastAt,
    this.lastSenderRole,
    this.unread = 0,
  });

  final String patientId;
  final String? patientName;
  final String? patientPhone;
  final String? lastMessage;
  final DateTime? lastAt;
  final String? lastSenderRole;
  final int unread;

  factory MessageThread.fromJson(Map<String, dynamic> j) => MessageThread(
    patientId: j['patientId']?.toString() ?? '',
    patientName: j['patientName']?.toString(),
    patientPhone: j['patientPhone']?.toString(),
    lastMessage: j['lastMessage']?.toString(),
    lastAt: DateTime.tryParse(j['lastAt']?.toString() ?? '')?.toLocal(),
    lastSenderRole: j['lastSenderRole']?.toString(),
    unread: (j['unread'] as num?)?.toInt() ?? 0,
  );
}

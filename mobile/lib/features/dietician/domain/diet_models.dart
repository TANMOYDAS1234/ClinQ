/// A patient assigned to the dietician (`GET /dietician/patients`).
class DietPatient {
  const DietPatient({
    required this.id,
    required this.name,
    required this.phone,
    this.avatarAssetId,
    this.diabetesType,
    required this.riskBand,
    this.reviewIntervalDays,
    this.lastReviewAt,
    required this.reviewDue,
  });

  final String id;
  final String name;
  final String phone;
  final String? avatarAssetId;
  final String? diabetesType;
  final String riskBand; // low | moderate | high | critical
  final int? reviewIntervalDays;
  final DateTime? lastReviewAt;
  final bool reviewDue;

  factory DietPatient.fromJson(Map<String, dynamic> j) => DietPatient(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        phone: j['phone']?.toString() ?? '',
        avatarAssetId: j['avatarAssetId']?.toString(),
        diabetesType: j['diabetesType']?.toString(),
        riskBand: j['riskBand']?.toString() ?? 'low',
        reviewIntervalDays: (j['reviewIntervalDays'] as num?)?.toInt(),
        lastReviewAt: DateTime.tryParse(j['lastReviewAt']?.toString() ?? '')?.toLocal(),
        reviewDue: j['reviewDue'] == true,
      );
}

/// One medicine the doctor has the patient on (nutrition context).
class DietMed {
  const DietMed({required this.name, required this.strength, required this.dose, required this.times});

  final String name;
  final String strength;
  final String dose;
  final List<String> times;

  factory DietMed.fromJson(Map<String, dynamic> j) => DietMed(
        name: j['name']?.toString() ?? '',
        strength: j['strength']?.toString() ?? '',
        dose: j['dose']?.toString() ?? '',
        times: (j['times'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
}

/// The nutrition-relevant view of a patient (`.../overview`).
class DietPatientOverview {
  const DietPatientOverview({
    required this.id,
    required this.name,
    required this.phone,
    this.gender,
    this.diabetesType,
    required this.riskBand,
    this.heightCm,
    required this.allergies,
    required this.medications,
    this.reviewIntervalDays,
  });

  final String id;
  final String name;
  final String phone;
  final String? gender;
  final String? diabetesType;
  final String riskBand;
  final int? heightCm;
  final List<String> allergies;
  final List<DietMed> medications;
  final int? reviewIntervalDays;

  factory DietPatientOverview.fromJson(Map<String, dynamic> j) {
    final p = j['patient'] as Map<String, dynamic>? ?? const {};
    final m = j['medical'] as Map<String, dynamic>? ?? const {};
    return DietPatientOverview(
      id: p['id']?.toString() ?? '',
      name: p['name']?.toString() ?? '',
      phone: p['phone']?.toString() ?? '',
      gender: p['gender']?.toString(),
      diabetesType: m['diabetesType']?.toString(),
      riskBand: m['riskBand']?.toString() ?? 'low',
      heightCm: (m['heightCm'] as num?)?.toInt(),
      allergies: (m['allergies'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      medications: (j['medications'] as List?)?.whereType<Map<String, dynamic>>().map(DietMed.fromJson).toList() ?? const [],
      reviewIntervalDays: (j['reviewIntervalDays'] as num?)?.toInt(),
    );
  }
}

/// One message in the patient's care thread, as the dietician sees it.
class DietMessage {
  const DietMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.attachments,
    this.senderName,
    this.createdAt,
  });

  final String id;
  final String role; // user | assistant | clinician | dietician | system
  final String content;
  final List<String> attachments;
  final String? senderName;
  final DateTime? createdAt;

  bool get fromPatient => role == 'user';
  bool get fromDietician => role == 'dietician';

  factory DietMessage.fromJson(Map<String, dynamic> j) => DietMessage(
        id: j['id']?.toString() ?? '',
        role: j['role']?.toString() ?? 'user',
        content: j['content']?.toString() ?? '',
        attachments: (j['attachments'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        senderName: j['senderName']?.toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
      );
}

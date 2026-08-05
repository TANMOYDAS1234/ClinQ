import 'clinician_models.dart';

/// A quarterly HbA1c point on the patient's record.
class Hba1cPoint {
  const Hba1cPoint({required this.percentage, this.testedOn});
  final num percentage;
  final DateTime? testedOn;

  factory Hba1cPoint.fromJson(Map<String, dynamic> j) => Hba1cPoint(
    percentage: (j['percentage'] as num?) ?? 0,
    testedOn: DateTime.tryParse(j['testedOn']?.toString() ?? '')?.toLocal(),
  );
}

/// A test report the patient uploaded against a doctor-advised test.
class LabReport {
  const LabReport({required this.id, required this.testName, required this.note, this.photoUrl, this.createdAt});
  final String id;
  final String testName;
  final String note;
  final String? photoUrl;
  final DateTime? createdAt;

  factory LabReport.fromJson(Map<String, dynamic> j) => LabReport(
    id: j['id']?.toString() ?? '',
    testName: j['testName']?.toString() ?? '',
    note: j['note']?.toString() ?? '',
    photoUrl: (j['photoUrl'] == null || j['photoUrl'].toString().isEmpty) ? null : j['photoUrl'].toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
  );
}

/// The full clinical picture for one patient (`GET /doctor/patients/:id/summary`).
/// Only the fields the clinician UI renders are pulled out; the raw analytics
/// blobs are large and screen-specific.
class PatientSummary {
  const PatientSummary({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.gender,
    this.age,
    this.language,
    this.avatarUrl,
    this.diabetesType,
    this.riskBand,
    this.riskScore,
    this.healthScore,
    this.healthBand,
    this.adherencePercent,
    this.glucoseAverage,
    this.timeInRangePercent,
    this.estimatedHba1c,
    this.hba1cHistory = const [],
    this.labResults = const [],
    this.alerts = const [],
    this.aiContext,
    this.assignedDieticianId,
    this.assignedDieticianName,
    this.reviewIntervalDays,
  });

  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? gender;
  final int? age;
  final String? language;

  /// Relative `/api/v1/uploads/:id/raw` path of the photo the patient set.
  final String? avatarUrl;

  /// A short, human-quotable form of the record id — the last six characters of
  /// the ObjectId. Not a second identifier: it is the same id, shortened, so a
  /// doctor reading a number over the phone is still reading the real one.
  String get shortId => id.length <= 6 ? id.toUpperCase() : 'P-${id.substring(id.length - 6).toUpperCase()}';

  final String? diabetesType;
  final String? riskBand;
  final int? riskScore;

  final int? healthScore;
  final String? healthBand;
  final int? adherencePercent;

  final int? glucoseAverage;
  final int? timeInRangePercent;
  final double? estimatedHba1c;

  final List<Hba1cPoint> hba1cHistory;
  final List<LabReport> labResults;
  final List<ClinicalAlert> alerts;
  final String? aiContext;

  final String? assignedDieticianId;
  final String? assignedDieticianName;
  final int? reviewIntervalDays;

  factory PatientSummary.fromJson(Map<String, dynamic> j) {
    final patient = j['patient'] as Map<String, dynamic>? ?? const {};
    final profile = j['profile'] as Map<String, dynamic>? ?? const {};
    final health = j['healthScore'] as Map<String, dynamic>? ?? const {};
    final adherence = j['adherence'] as Map<String, dynamic>? ?? const {};
    final trends = j['trends'] as Map<String, dynamic>? ?? const {};
    final stats = trends['stats'] as Map<String, dynamic>?;

    return PatientSummary(
      id: patient['id']?.toString() ?? '',
      name: patient['name']?.toString() ?? '',
      phone: patient['phone']?.toString() ?? '',
      email: patient['email']?.toString(),
      gender: patient['gender']?.toString(),
      age: (patient['age'] as num?)?.toInt(),
      language: patient['language']?.toString(),
      avatarUrl: patient['avatarUrl']?.toString(),
      diabetesType: profile['diabetesType']?.toString(),
      riskBand: profile['riskBand']?.toString(),
      riskScore: (profile['riskScore'] as num?)?.toInt(),
      assignedDieticianId: profile['assignedDietician'] is Map
          ? (profile['assignedDietician'] as Map)['_id']?.toString()
          : profile['assignedDietician']?.toString(),
      assignedDieticianName: profile['assignedDietician'] is Map
          ? (profile['assignedDietician'] as Map)['name']?.toString()
          : null,
      reviewIntervalDays: (profile['dietReviewIntervalDays'] as num?)?.toInt(),
      labResults: (j['labResults'] as List?)?.whereType<Map<String, dynamic>>().map(LabReport.fromJson).toList() ?? const [],
      healthScore: (health['score'] as num?)?.toInt(),
      healthBand: health['band']?.toString(),
      adherencePercent: (adherence['percentage'] as num?)?.toInt(),
      glucoseAverage: (stats?['average'] as num?)?.toInt(),
      timeInRangePercent: (stats?['timeInRangePercent'] as num?)?.toInt(),
      estimatedHba1c: (stats?['estimatedHba1c'] as num?)?.toDouble(),
      hba1cHistory: (j['hba1cHistory'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(Hba1cPoint.fromJson)
              .toList() ??
          const [],
      alerts: (j['alerts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(ClinicalAlert.fromJson)
              .toList() ??
          const [],
      aiContext: j['aiContext']?.toString(),
    );
  }
}

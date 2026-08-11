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

/// One day's glucose summary — the point the continuous-monitoring graph plots.
class GlucoseDailyPoint {
  const GlucoseDailyPoint({required this.date, required this.average, required this.min, required this.max});
  final DateTime date;
  final int average;
  final int min;
  final int max;

  factory GlucoseDailyPoint.fromJson(Map<String, dynamic> j) => GlucoseDailyPoint(
    date: DateTime.tryParse(j['date']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    average: (j['average'] as num?)?.toInt() ?? 0,
    min: (j['min'] as num?)?.toInt() ?? 0,
    max: (j['max'] as num?)?.toInt() ?? 0,
  );
}

/// One structured reading transcribed from a report — value, unit, reference
/// window and a low/normal/high flag.
class Analyte {
  const Analyte({
    required this.code,
    required this.label,
    required this.value,
    required this.flag,
    this.unit,
    this.refLow,
    this.refHigh,
  });

  final String code;
  final String label;
  final num value;
  final String? unit;
  final num? refLow;
  final num? refHigh;
  final String flag; // low | normal | high | critical

  bool get abnormal => flag == 'low' || flag == 'high' || flag == 'critical';

  /// A compact reference window, e.g. "70–130", "<100", ">40".
  String get rangeText {
    String n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    if (refLow != null && refHigh != null) return '${n(refLow!)}–${n(refHigh!)}';
    if (refHigh != null) return '<${n(refHigh!)}';
    if (refLow != null) return '>${n(refLow!)}';
    return '';
  }

  factory Analyte.fromJson(Map<String, dynamic> j) => Analyte(
    code: j['code']?.toString() ?? '',
    label: j['label']?.toString() ?? '',
    value: (j['value'] as num?) ?? 0,
    unit: j['unit']?.toString(),
    refLow: j['refLow'] as num?,
    refHigh: j['refHigh'] as num?,
    flag: j['flag']?.toString() ?? 'normal',
  );
}

/// A test report the patient uploaded against a doctor-advised test.
class LabReport {
  const LabReport({
    required this.id,
    required this.testName,
    required this.note,
    this.photoUrl,
    this.createdAt,
    this.mimeType,
    this.originalName,
    this.analysisStatus,
    this.analysisSummary,
    this.analytes = const [],
  });
  final String id;
  final String testName;
  final String note;
  final String? photoUrl;
  final DateTime? createdAt;
  final String? mimeType;
  final String? originalName;

  /// pending | done | failed | unsupported — so "couldn't read it" reads
  /// differently from "nothing on it".
  final String? analysisStatus;
  final String? analysisSummary;

  /// The structured values transcribed off the report, with ranges + flags.
  final List<Analyte> analytes;

  /// Labs email PDFs, so most reports are not pictures. Unknown types count as
  /// documents — a file card that opens beats an image box that cannot load.
  bool get isImage => mimeType?.startsWith('image/') ?? false;
  bool get hasFile => photoUrl != null && photoUrl!.isNotEmpty;

  factory LabReport.fromJson(Map<String, dynamic> j) => LabReport(
    id: j['id']?.toString() ?? '',
    testName: j['testName']?.toString() ?? '',
    note: j['note']?.toString() ?? '',
    photoUrl: (j['photoUrl'] == null || j['photoUrl'].toString().isEmpty) ? null : j['photoUrl'].toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
    mimeType: j['mimeType']?.toString(),
    originalName: j['originalName']?.toString(),
    analysisStatus: j['analysisStatus']?.toString(),
    analysisSummary: j['analysisSummary']?.toString(),
    analytes: (j['analytes'] as List?)?.whereType<Map<String, dynamic>>().map(Analyte.fromJson).toList() ?? const [],
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
    this.glucoseDaily = const [],
    this.labResults = const [],
    this.advisedTests = const [],
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

  /// Per-day glucose averages (with min/max) — the continuous-monitoring series.
  final List<GlucoseDailyPoint> glucoseDaily;

  final List<LabReport> labResults;

  /// Tests already ordered on an active prescription — so the doctor can see
  /// what is outstanding before ordering it again.
  final List<String> advisedTests;
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
      advisedTests: (j['labTestsAdvised'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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
      glucoseDaily: (trends['daily'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(GlucoseDailyPoint.fromJson)
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

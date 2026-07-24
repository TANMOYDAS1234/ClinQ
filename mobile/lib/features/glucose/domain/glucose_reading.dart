/// Matches the `reading` object returned by `POST /glucose` and the items
/// of `GET /glucose` (API_CONTRACT.md §3).
class GlucoseReading {
  const GlucoseReading({
    required this.id,
    required this.valueMgDl,
    required this.context,
    required this.measuredAt,
    required this.flag,
    this.notes,
    this.source,
    this.createdAt,
  });

  final String id;
  final num valueMgDl;

  /// fasting | pre_meal | post_meal | bedtime | random.
  final String context;
  final DateTime? measuredAt;

  /// severe_low | low | in_range | very_high | critical_high.
  final String flag;
  final String? notes;
  final String? source;
  final DateTime? createdAt;

  factory GlucoseReading.fromJson(Map<String, dynamic> json) {
    return GlucoseReading(
      id: json['id']?.toString() ?? '',
      valueMgDl: json['valueMgDl'] as num? ?? 0,
      context: json['context']?.toString() ?? 'random',
      measuredAt: json['measuredAt'] == null ? null : DateTime.tryParse(json['measuredAt'].toString()),
      flag: json['flag']?.toString() ?? 'in_range',
      notes: json['notes'] as String?,
      source: json['source'] as String?,
      createdAt: json['createdAt'] == null ? null : DateTime.tryParse(json['createdAt'].toString()),
    );
  }
}

class GlucoseAssessment {
  const GlucoseAssessment({required this.flag, required this.urgency, required this.summary});

  final String flag;
  final String urgency;
  final String summary;

  factory GlucoseAssessment.fromJson(Map<String, dynamic> json) {
    return GlucoseAssessment(
      flag: json['flag']?.toString() ?? 'in_range',
      urgency: json['urgency']?.toString() ?? 'routine',
      summary: json['summary']?.toString() ?? '',
    );
  }
}

/// Same minimal alert shape used across §2/§3/§4: `{id, severity, type,
/// title}`. Kept local to this feature per the architecture's
/// one-model-per-feature convention (see chat's `ChatAlert`).
class GlucoseAlert {
  const GlucoseAlert({
    required this.id,
    required this.severity,
    required this.type,
    required this.title,
  });

  final String id;
  final String severity;
  final String type;
  final String title;

  factory GlucoseAlert.fromJson(Map<String, dynamic> json) {
    return GlucoseAlert(
      id: json['id']?.toString() ?? '',
      severity: json['severity']?.toString() ?? 'routine',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
    );
  }
}

/// Response of `POST /glucose`.
class LogGlucoseResult {
  const LogGlucoseResult({required this.reading, required this.assessment, this.alert});

  final GlucoseReading reading;
  final GlucoseAssessment assessment;
  final GlucoseAlert? alert;

  factory LogGlucoseResult.fromJson(Map<String, dynamic> json) {
    return LogGlucoseResult(
      reading: GlucoseReading.fromJson(json['reading'] as Map<String, dynamic>),
      assessment: GlucoseAssessment.fromJson(json['assessment'] as Map<String, dynamic>? ?? const {}),
      alert: json['alert'] == null
          ? null
          : GlucoseAlert.fromJson(json['alert'] as Map<String, dynamic>),
    );
  }
}

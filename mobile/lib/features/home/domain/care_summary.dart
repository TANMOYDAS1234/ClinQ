/// The patient's own view of their care, from `GET /dashboard`.
///
/// Deliberately a read-only picture: what the clinic has decided about them,
/// what they have been asked to eat, what they are taking, and what they have
/// logged. Everything actionable lives on the tabs beside it.
class CareSummary {
  const CareSummary({
    required this.profile,
    this.latestHba1c,
    this.dietPlan,
    this.medications = const [],
    this.recentFoodLogs = const [],
  });

  final CareProfile profile;
  final Hba1cResult? latestHba1c;
  final PatientDietPlan? dietPlan;
  final List<CareMedication> medications;
  final List<CareFoodLog> recentFoodLogs;

  factory CareSummary.fromJson(Map<String, dynamic> j) => CareSummary(
    profile: CareProfile.fromJson(j['profile'] as Map<String, dynamic>? ?? const {}),
    latestHba1c: j['latestHba1c'] is Map
        ? Hba1cResult.fromJson(Map<String, dynamic>.from(j['latestHba1c'] as Map))
        : null,
    dietPlan: j['dietPlan'] is Map
        ? PatientDietPlan.fromJson(Map<String, dynamic>.from(j['dietPlan'] as Map))
        : null,
    medications:
        (j['medications'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(CareMedication.fromJson)
            .toList() ??
        const [],
    recentFoodLogs:
        (j['recentFoodLogs'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(CareFoodLog.fromJson)
            .toList() ??
        const [],
  );
}

class CareProfile {
  const CareProfile({
    this.diabetesType,
    this.riskBand,
    this.heightCm,
    this.weightKg,
    this.bmi,
    this.allergies = const [],
    this.reviewIntervalDays,
  });

  final String? diabetesType;

  /// The clinic's own assessment, shown beside the patient's name. Set by the
  /// doctor, not computed here.
  final String? riskBand;

  final int? heightCm;
  final num? weightKg;
  final num? bmi;
  final List<String> allergies;
  final int? reviewIntervalDays;

  String? get conditionLabel => switch (diabetesType) {
    'type1' => 'Type 1 Diabetes',
    'type2' => 'Type 2 Diabetes',
    'gestational' => 'Gestational Diabetes',
    'prediabetes' => 'Prediabetes',
    'none' => 'Not diabetic',
    _ => null,
  };

  /// Only the bands worth flagging get a badge — "Low Risk" beside someone's
  /// name is a label doing no work.
  bool get showRisk => riskBand == 'high' || riskBand == 'critical' || riskBand == 'moderate';

  String get riskLabel => switch (riskBand) {
    'critical' => 'Critical Risk',
    'high' => 'High Risk',
    'moderate' => 'Moderate Risk',
    _ => 'Low Risk',
  };

  /// "Every 2 weeks" reads better than "14 days" for the rhythms a clinic uses.
  String? get reviewLabel => switch (reviewIntervalDays) {
    null => null,
    1 => 'Daily',
    3 => 'Every 3 days',
    7 => 'Weekly',
    14 => 'Every 2 weeks',
    30 => 'Monthly',
    final d => 'Every $d days',
  };

  factory CareProfile.fromJson(Map<String, dynamic> j) => CareProfile(
    diabetesType: j['diabetesType']?.toString(),
    riskBand: j['riskBand']?.toString(),
    heightCm: (j['heightCm'] as num?)?.toInt(),
    weightKg: j['weightKg'] as num?,
    bmi: j['bmi'] as num?,
    allergies: (j['allergies'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    reviewIntervalDays: (j['reviewIntervalDays'] as num?)?.toInt(),
  );
}

class Hba1cResult {
  const Hba1cResult({required this.percentage, this.testedOn, this.isHigh = false});

  final num percentage;
  final DateTime? testedOn;

  /// Measured against this patient's own target, set by the doctor — not a
  /// textbook threshold.
  final bool isHigh;

  factory Hba1cResult.fromJson(Map<String, dynamic> j) => Hba1cResult(
    percentage: j['percentage'] as num? ?? 0,
    testedOn: DateTime.tryParse(j['testedOn']?.toString() ?? '')?.toLocal(),
    isHigh: j['isHigh'] == true,
  );
}

class PatientDietPlan {
  const PatientDietPlan({
    this.goal = '',
    this.meals = const [],
    this.avoid = const [],
    this.notes = '',
    this.dieticianName,
    this.sharedAt,
  });

  final String goal;
  final List<PlanMeal> meals;
  final List<String> avoid;
  final String notes;
  final String? dieticianName;
  final DateTime? sharedAt;

  factory PatientDietPlan.fromJson(Map<String, dynamic> j) => PatientDietPlan(
    goal: j['goal']?.toString() ?? '',
    meals:
        (j['meals'] as List?)?.whereType<Map<String, dynamic>>().map(PlanMeal.fromJson).toList() ??
        const [],
    avoid: (j['avoid'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    notes: j['notes']?.toString() ?? '',
    dieticianName: j['dieticianName']?.toString(),
    sharedAt: DateTime.tryParse(j['sharedAt']?.toString() ?? '')?.toLocal(),
  );
}

class PlanMeal {
  const PlanMeal({required this.name, this.time = '', this.items = const [], this.notes = ''});

  final String name;
  final String time;
  final List<String> items;
  final String notes;

  /// One line for the card face; the full list is on the detail sheet.
  String get summary => items.isNotEmpty ? items.join(', ') : notes;

  factory PlanMeal.fromJson(Map<String, dynamic> j) => PlanMeal(
    name: j['name']?.toString() ?? '',
    time: j['time']?.toString() ?? '',
    items: (j['items'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    notes: j['notes']?.toString() ?? '',
  );
}

class CareMedication {
  const CareMedication({
    required this.id,
    required this.name,
    this.strength = '',
    this.dose = '',
    this.instructions = '',
    this.times = const [],
  });

  final String id;
  final String name;
  final String strength;
  final String dose;
  final String instructions;
  final List<String> times;

  String get title => strength.isEmpty ? name : '$name $strength';

  /// "Twice daily with meals" from the schedule the doctor set, rather than a
  /// raw list of clock times.
  String get scheduleLabel {
    if (instructions.isNotEmpty) return instructions;
    final n = times.length;
    final how = switch (n) {
      0 => 'As needed',
      1 => 'Once daily',
      2 => 'Twice daily',
      3 => 'Three times daily',
      _ => '$n times daily',
    };
    if (n == 0) return how;
    return '$how at ${times.join(', ')}';
  }

  factory CareMedication.fromJson(Map<String, dynamic> j) => CareMedication(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    strength: j['strength']?.toString() ?? '',
    dose: j['dose']?.toString() ?? '',
    instructions: j['instructions']?.toString() ?? '',
    times: (j['times'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

class CareFoodLog {
  const CareFoodLog({
    required this.id,
    required this.mealType,
    this.note = '',
    this.photoUrl,
    this.createdAt,
  });

  final String id;
  final String mealType;
  final String note;
  final String? photoUrl;
  final DateTime? createdAt;

  factory CareFoodLog.fromJson(Map<String, dynamic> j) => CareFoodLog(
    id: j['id']?.toString() ?? '',
    mealType: j['mealType']?.toString() ?? '',
    note: j['note']?.toString() ?? '',
    photoUrl: j['photoUrl']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
  );
}

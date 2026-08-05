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
    this.advisedTests = const [],
    this.latestHba1c,
    this.hba1cTestedOn,
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

  /// Lab work the doctor ordered, and whether a result has come back. An
  /// advised-but-missing test is why a diet plan may be resting on stale
  /// numbers, so it is worth seeing before writing one.
  final List<AdvisedTest> advisedTests;
  final num? latestHba1c;
  final DateTime? hba1cTestedOn;

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
      advisedTests:
          ((j['labTests'] as Map<String, dynamic>?)?['advised'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(AdvisedTest.fromJson)
              .toList() ??
          const [],
      latestHba1c:
          ((j['labTests'] as Map<String, dynamic>?)?['latestHba1c'] as Map<String, dynamic>?)?['percentage']
              as num?,
      hba1cTestedOn: DateTime.tryParse(
        ((j['labTests'] as Map<String, dynamic>?)?['latestHba1c']
                as Map<String, dynamic>?)?['testedOn']
                ?.toString() ??
            '',
      )?.toLocal(),
    );
  }
}

/// One meal in a diet plan. `name` and `time` are free text on purpose — an
/// Indian day is not breakfast/lunch/dinner, and "before namaz" has to be
/// sayable.
class DietMeal {
  const DietMeal({
    required this.name,
    this.time = '',
    this.items = const [],
    this.notes = '',
  });

  final String name;
  final String time;
  final List<String> items;
  final String notes;

  DietMeal copyWith({String? name, String? time, List<String>? items, String? notes}) => DietMeal(
    name: name ?? this.name,
    time: time ?? this.time,
    items: items ?? this.items,
    notes: notes ?? this.notes,
  );

  Map<String, dynamic> toJson() => {'name': name, 'time': time, 'items': items, 'notes': notes};

  factory DietMeal.fromJson(Map<String, dynamic> j) => DietMeal(
    name: j['name']?.toString() ?? '',
    time: j['time']?.toString() ?? '',
    items: (j['items'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    notes: j['notes']?.toString() ?? '',
  );
}

/// The patient's diet plan. One per patient — a second would mean two answers
/// to "what do I eat", which is worse than none.
class DietPlan {
  const DietPlan({
    this.goal = '',
    this.meals = const [],
    this.avoid = const [],
    this.notes = '',
    this.dieticianName,
    this.sharedAt,
    this.updatedAt,
  });

  final String goal;
  final List<DietMeal> meals;
  final List<String> avoid;
  final String notes;
  final String? dieticianName;

  /// When the plan was last pushed into the care thread. Null means the patient
  /// has never been shown it — a finished-looking draft is still a draft.
  final DateTime? sharedAt;
  final DateTime? updatedAt;

  bool get isEmpty => goal.isEmpty && meals.isEmpty && avoid.isEmpty && notes.isEmpty;

  /// True when the dietician has edited the plan since the patient last saw it.
  bool get hasUnsentChanges =>
      !isEmpty && (sharedAt == null || (updatedAt != null && updatedAt!.isAfter(sharedAt!)));

  Map<String, dynamic> toJson() => {
    'goal': goal,
    'meals': meals.map((m) => m.toJson()).toList(),
    'avoid': avoid,
    'notes': notes,
  };

  factory DietPlan.fromJson(Map<String, dynamic> j) => DietPlan(
    goal: j['goal']?.toString() ?? '',
    meals: (j['meals'] as List?)?.whereType<Map<String, dynamic>>().map(DietMeal.fromJson).toList() ?? const [],
    avoid: (j['avoid'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    notes: j['notes']?.toString() ?? '',
    dieticianName: j['dieticianName']?.toString(),
    sharedAt: DateTime.tryParse(j['sharedAt']?.toString() ?? '')?.toLocal(),
    updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '')?.toLocal(),
  );
}

/// A patient as the dashboard lists them — enough to decide whether to open it.
class DietPatientBrief {
  const DietPatientBrief({
    required this.id,
    required this.name,
    this.avatarAssetId,
    required this.riskBand,
    this.diabetesType,
    this.reviewIntervalDays,
    this.lastReviewAt,
    this.sinceDays = 0,
  });

  final String id;
  final String name;
  final String? avatarAssetId;
  final String riskBand;
  final String? diabetesType;
  final int? reviewIntervalDays;
  final DateTime? lastReviewAt;

  /// Days since the last review, or since the record started if never reviewed.
  final int sinceDays;

  factory DietPatientBrief.fromJson(Map<String, dynamic> j) => DietPatientBrief(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    avatarAssetId: j['avatarAssetId']?.toString(),
    riskBand: j['riskBand']?.toString() ?? 'low',
    diabetesType: j['diabetesType']?.toString(),
    reviewIntervalDays: (j['reviewIntervalDays'] as num?)?.toInt(),
    lastReviewAt: DateTime.tryParse(j['lastReviewAt']?.toString() ?? '')?.toLocal(),
    sinceDays: (j['sinceDays'] as num?)?.toInt() ?? 0,
  );
}

/// One row in the dietician's action queue: either a review that has come due
/// or a patient still waiting for a plan.
class DietQueueItem {
  const DietQueueItem({
    required this.patientId,
    required this.name,
    required this.days,
    required this.needsPlan,
  });

  final String patientId;
  final String name;
  final int days;
  final bool needsPlan;

  String get label => '${days}d';
}

/// A meal one of the dietician's patients logged, for the dashboard feed.
class DietRecentLog {
  const DietRecentLog({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.mealType,
    required this.note,
    this.photoUrl,
    this.createdAt,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String mealType;
  final String note;
  final String? photoUrl;
  final DateTime? createdAt;

  factory DietRecentLog.fromJson(Map<String, dynamic> j) => DietRecentLog(
    id: j['id']?.toString() ?? '',
    patientId: j['patientId']?.toString() ?? '',
    patientName: j['patientName']?.toString() ?? '',
    mealType: j['mealType']?.toString() ?? '',
    note: j['note']?.toString() ?? '',
    photoUrl: j['photoUrl']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
  );
}

/// Everything the dietician's dashboard shows, in one response — so the three
/// counts always agree with the three lists below them.
class DietDashboard {
  const DietDashboard({
    required this.patients,
    this.newThisWeek = 0,
    required this.reviewsDue,
    required this.plansMissing,
    required this.reviewsDueList,
    required this.plansMissingList,
    required this.recentLogs,
  });

  final int patients;

  /// Patients whose record was opened in the last seven days.
  final int newThisWeek;

  final int reviewsDue;
  final int plansMissing;
  final List<DietPatientBrief> reviewsDueList;
  final List<DietPatientBrief> plansMissingList;
  final List<DietRecentLog> recentLogs;

  /// Reviews due, longest-waiting first, with anyone who has no plan at all
  /// left out — they belong under "waiting for a plan", not under "overdue for
  /// review", and a patient in both lists twice reads as twice the work.
  List<DietPatientBrief> get reviewsSorted {
    final planIds = plansMissingList.map((p) => p.id).toSet();
    return [...reviewsDueList.where((p) => !planIds.contains(p.id))]
      ..sort((a, b) => b.sinceDays.compareTo(a.sinceDays));
  }

  List<DietPatientBrief> get plansSorted =>
      [...plansMissingList]..sort((a, b) => b.sinceDays.compareTo(a.sinceDays));

  /// The two worklists as one queue. Reviews first: a patient already on a plan
  /// whose review has lapsed is care going stale, which outranks care not yet
  /// started. Longest-waiting first within each, and a patient in both lists
  /// appears once — as the plan they still do not have.
  List<DietQueueItem> get queue {
    final planIds = plansMissingList.map((p) => p.id).toSet();
    final sortedReviews = [...reviewsDueList.where((p) => !planIds.contains(p.id))]
      ..sort((a, b) => b.sinceDays.compareTo(a.sinceDays));
    final sortedPlans = [...plansMissingList]..sort((a, b) => b.sinceDays.compareTo(a.sinceDays));

    return [
      for (final p in sortedReviews)
        DietQueueItem(patientId: p.id, name: p.name, days: p.sinceDays, needsPlan: false),
      for (final p in sortedPlans)
        DietQueueItem(patientId: p.id, name: p.name, days: p.sinceDays, needsPlan: true),
    ];
  }

  factory DietDashboard.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] as Map<String, dynamic>? ?? const {};
    List<DietPatientBrief> briefs(String key) =>
        (j[key] as List?)?.whereType<Map<String, dynamic>>().map(DietPatientBrief.fromJson).toList() ?? const [];
    return DietDashboard(
      patients: (counts['patients'] as num?)?.toInt() ?? 0,
      newThisWeek: (counts['newThisWeek'] as num?)?.toInt() ?? 0,
      reviewsDue: (counts['reviewsDue'] as num?)?.toInt() ?? 0,
      plansMissing: (counts['plansMissing'] as num?)?.toInt() ?? 0,
      reviewsDueList: briefs('reviewsDue'),
      plansMissingList: briefs('plansMissing'),
      recentLogs:
          (j['recentLogs'] as List?)?.whereType<Map<String, dynamic>>().map(DietRecentLog.fromJson).toList() ??
          const [],
    );
  }
}

/// A lab test the doctor ordered, and whether a result has come back.
class AdvisedTest {
  const AdvisedTest({required this.name, required this.reported});

  final String name;
  final bool reported;

  factory AdvisedTest.fromJson(Map<String, dynamic> j) => AdvisedTest(
    name: j['name']?.toString() ?? '',
    reported: j['reported'] == true,
  );
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

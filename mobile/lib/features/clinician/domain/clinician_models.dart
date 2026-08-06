/// Dashboard headline numbers from `GET /doctor/overview`.
class ClinicOverview {
  const ClinicOverview({
    required this.patientCount,
    this.newPatientsToday = 0,
    required this.activeToday,
    required this.appointmentsToday,
    required this.completedToday,
    required this.pendingReviews,
    required this.unreadMessages,
    this.unreadNutrition = 0,
    required this.emergencyAlerts,
    required this.urgentAlerts,
    required this.warningAlerts,
    required this.totalOpenAlerts,
    required this.riskLow,
    required this.riskModerate,
    required this.riskHigh,
    required this.riskCritical,
    this.dietPatients = 0,
    this.foodLogsToday = 0,
    this.nutritionReviews = const [],
  });

  final int patientCount;

  /// Patients who registered today — the "+3 today" next to the headline count.
  final int newPatientsToday;

  final int activeToday;
  final int appointmentsToday;

  /// Today's finished consultations — the "Completed" headline tile.
  final int completedToday;

  /// Conversations flagged for the doctor to read — the "Pending" tile.
  final int pendingReviews;

  /// Patient messages the clinic has not opened yet — the "New Messages" alert.
  final int unreadMessages;

  /// How many of [unreadMessages] are in a nutrition thread — which the doctor
  /// reaches through Chat review, not the Patients tab.
  final int unreadNutrition;

  final int emergencyAlerts;
  final int urgentAlerts;
  final int warningAlerts;
  final int totalOpenAlerts;
  final int riskLow;
  final int riskModerate;
  final int riskHigh;
  final int riskCritical;

  /// Patients a doctor has assigned to a dietician, and meals logged today.
  final int dietPatients;
  final int foodLogsToday;

  /// The patients on a review cadence, closest to their review date first.
  final List<NutritionReview> nutritionReviews;

  /// Open alerts that need immediate eyes — the "High Priority" alert count.
  int get highPriorityAlerts => emergencyAlerts + urgentAlerts;

  factory ClinicOverview.fromJson(Map<String, dynamic> j) {
    final alerts = j['openAlerts'] as Map<String, dynamic>? ?? const {};
    final risk = j['riskDistribution'] as Map<String, dynamic>? ?? const {};
    final nutrition = j['nutrition'] as Map<String, dynamic>? ?? const {};
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;
    return ClinicOverview(
      patientCount: n(j['patientCount']),
      newPatientsToday: n(j['newPatientsToday']),
      activeToday: n(j['activeToday']),
      appointmentsToday: n(j['appointmentsToday']),
      completedToday: n(j['completedToday']),
      pendingReviews: n(j['pendingReviews']),
      unreadMessages: n(j['unreadMessages']),
      unreadNutrition: n(j['unreadNutrition']),
      emergencyAlerts: n(alerts['emergency']),
      urgentAlerts: n(alerts['urgent']),
      warningAlerts: n(alerts['warning']),
      totalOpenAlerts: n(alerts['total']),
      riskLow: n(risk['low']),
      riskModerate: n(risk['moderate']),
      riskHigh: n(risk['high']),
      riskCritical: n(risk['critical']),
      dietPatients: n(nutrition['dietPatients']),
      foodLogsToday: n(nutrition['foodLogsToday']),
      nutritionReviews:
          (nutrition['reviews'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(NutritionReview.fromJson)
              .toList() ??
          const [],
    );
  }
}

/// One nutrition card on the doctor's home: where a patient is in their review
/// cycle, and what their logging actually looks like.
class NutritionReview {
  const NutritionReview({
    required this.patientId,
    required this.name,
    required this.day,
    required this.intervalDays,
    required this.mealsThisWeek,
    this.lastLogAt,
  });

  final String patientId;
  final String name;

  /// Days into the current review cycle — the "Day 14/30" on the card.
  final int day;
  final int intervalDays;
  final int mealsThisWeek;
  final DateTime? lastLogAt;

  bool get isDue => intervalDays > 0 && day >= intervalDays;

  /// The headline on the card. Derived from logging activity rather than
  /// nutrient analysis: the app records meals, not sodium, and a card claiming
  /// otherwise would be inventing a number the doctor might act on.
  String get flag {
    if (lastLogAt == null) return 'Never logged a meal';
    final quiet = DateTime.now().difference(lastLogAt!).inDays;
    if (quiet >= 3) return 'Stopped logging';
    if (mealsThisWeek < 7) return 'Logging patchy';
    return 'Logging well';
  }

  String get detail {
    if (lastLogAt == null) return 'No meals recorded since joining';
    final quiet = DateTime.now().difference(lastLogAt!).inDays;
    if (quiet >= 3) return 'Nothing logged for $quiet days';
    return '$mealsThisWeek ${mealsThisWeek == 1 ? 'meal' : 'meals'} in the past week';
  }

  factory NutritionReview.fromJson(Map<String, dynamic> j) => NutritionReview(
    patientId: j['patientId']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    day: (j['day'] as num?)?.toInt() ?? 0,
    intervalDays: (j['intervalDays'] as num?)?.toInt() ?? 0,
    mealsThisWeek: (j['mealsThisWeek'] as num?)?.toInt() ?? 0,
    lastLogAt: DateTime.tryParse(j['lastLogAt']?.toString() ?? '')?.toLocal(),
  );
}

/// The doctor's Patients tab payload (`GET /doctor/worklist`).
class DoctorWorklist {
  const DoctorWorklist({
    required this.patients,
    required this.reviews,
    required this.plans,
    required this.queue,
    required this.recentMeals,
  });

  final int patients;
  final int reviews;
  final int plans;
  final List<WorklistItem> queue;
  final List<RecentMeal> recentMeals;

  factory DoctorWorklist.fromJson(Map<String, dynamic> j) {
    final counts = j['counts'] as Map<String, dynamic>? ?? const {};
    int n(dynamic v) => (v as num?)?.toInt() ?? 0;
    return DoctorWorklist(
      patients: n(counts['patients']),
      reviews: n(counts['reviews']),
      plans: n(counts['plans']),
      queue:
          (j['queue'] as List?)?.whereType<Map<String, dynamic>>().map(WorklistItem.fromJson).toList() ??
          const [],
      recentMeals:
          (j['recentMeals'] as List?)?.whereType<Map<String, dynamic>>().map(RecentMeal.fromJson).toList() ??
          const [],
    );
  }
}

/// One row in the doctor's action queue.
class WorklistItem {
  const WorklistItem({
    required this.kind,
    required this.patientId,
    required this.name,
    required this.days,
  });

  /// `review` — a conversation flagged for the doctor to read.
  /// `plan` — a patient who has never been prescribed for.
  final String kind;
  final String patientId;
  final String name;
  final int days;

  bool get needsPlan => kind == 'plan';

  factory WorklistItem.fromJson(Map<String, dynamic> j) => WorklistItem(
    kind: j['kind']?.toString() ?? 'review',
    patientId: j['patientId']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    days: (j['days'] as num?)?.toInt() ?? 0,
  );
}

/// A meal one of the clinic's patients logged, for the Latest Meals strip.
class RecentMeal {
  const RecentMeal({
    required this.id,
    required this.patientId,
    required this.patientName,
    required this.mealType,
    this.photoUrl,
    this.createdAt,
  });

  final String id;
  final String patientId;
  final String patientName;
  final String mealType;
  final String? photoUrl;
  final DateTime? createdAt;

  factory RecentMeal.fromJson(Map<String, dynamic> j) => RecentMeal(
    id: j['id']?.toString() ?? '',
    patientId: j['patientId']?.toString() ?? '',
    patientName: j['patientName']?.toString() ?? '',
    mealType: j['mealType']?.toString() ?? '',
    photoUrl: j['photoUrl']?.toString(),
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
  );
}

/// One row in the doctor's patient directory (`GET /doctor/patients`).
/// The newest turn in a patient's thread, for the clinician's inbox row.
class MessagePreview {
  const MessagePreview({
    required this.preview,
    required this.role,
    required this.at,
    this.urgency = 'routine',
    this.mediaType,
  });

  /// Already trimmed server-side — a 4000-character message has no business
  /// crossing the wire to fill a two-line row.
  final String preview;

  /// `user` | `assistant` | `clinician`. Lets the row say who spoke last, which
  /// is the difference between "waiting on you" and "already answered".
  final String role;
  final DateTime at;
  final String urgency;

  /// `voice` | `photo` | `pdf` | `document` | `file` when the newest turn is
  /// media, so the row can draw a subtle icon before the label. Null for text.
  final String? mediaType;

  bool get fromPatient => role == 'user';

  factory MessagePreview.fromJson(Map<String, dynamic> j) => MessagePreview(
    preview: j['preview']?.toString() ?? '',
    role: j['role']?.toString() ?? 'user',
    at: DateTime.tryParse(j['at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    urgency: j['urgency']?.toString() ?? 'routine',
    mediaType: j['mediaType']?.toString(),
  );
}

class PatientListItem {
  const PatientListItem({
    required this.id,
    required this.name,
    required this.phone,
    required this.riskScore,
    required this.riskBand,
    this.avatarUrl,
    this.lastMessage,
    this.unreadCount = 0,
    this.lastReadingAt,
    this.lastReadingValue,
    this.openAlertCount = 0,
  });

  final String id;
  final String name;
  final String phone;

  /// Relative `/api/v1/uploads/:id/raw` path of the photo the patient set, or
  /// null. Absolute URL and auth header are assembled at render time.
  final String? avatarUrl;

  /// Newest turn in this patient's thread, or null if they have never written.
  final MessagePreview? lastMessage;

  /// Patient messages no clinician has opened yet. Drives the unread badge.
  final int unreadCount;
  final int riskScore;
  final String riskBand; // low | moderate | high | critical
  final DateTime? lastReadingAt;
  final num? lastReadingValue;
  final int openAlertCount;

  factory PatientListItem.fromJson(Map<String, dynamic> j) => PatientListItem(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    phone: j['phone']?.toString() ?? '',
    riskScore: (j['riskScore'] as num?)?.toInt() ?? 0,
    riskBand: j['riskBand']?.toString() ?? 'low',
    avatarUrl: j['avatarUrl']?.toString(),
    // `is Map` rather than `is Map<String, dynamic>`: a nested object can decode
    // as Map<dynamic, dynamic> depending on the path it took, and the stricter
    // test would drop it silently. Defensive, not a fix for a known bug.
    lastMessage: j['lastMessage'] is Map
        ? MessagePreview.fromJson(Map<String, dynamic>.from(j['lastMessage'] as Map))
        : null,
    unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
    lastReadingAt: DateTime.tryParse(j['lastReadingAt']?.toString() ?? '')?.toLocal(),
    lastReadingValue: j['lastReadingValue'] as num?,
    openAlertCount: (j['openAlertCount'] as num?)?.toInt() ?? 0,
  );
}

/// A clinical alert (`GET /doctor/alerts`).
class ClinicalAlert {
  const ClinicalAlert({
    required this.id,
    required this.severity,
    required this.type,
    required this.title,
    required this.status,
    this.patientId,
    this.patientName,
    this.patientPhone,
    this.detail,
    this.matchedRules = const [],
    this.createdAt,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNotes,
  });

  final String id;
  final String severity; // emergency | urgent | warning | info
  final String type;
  final String title;
  final String status; // open | acknowledged | resolved | dismissed
  final String? patientId;
  final String? patientName;
  final String? patientPhone;
  final String? detail;
  final List<String> matchedRules;
  final DateTime? createdAt;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final String? resolutionNotes;

  bool get isOpen => status == 'open';
  bool get isResolved => status == 'resolved' || status == 'dismissed';

  factory ClinicalAlert.fromJson(Map<String, dynamic> j) => ClinicalAlert(
    id: j['id']?.toString() ?? '',
    severity: j['severity']?.toString() ?? 'warning',
    type: j['type']?.toString() ?? 'other',
    title: j['title']?.toString() ?? '',
    status: j['status']?.toString() ?? 'open',
    patientId: j['patientId']?.toString(),
    patientName: j['patientName']?.toString(),
    patientPhone: j['patientPhone']?.toString(),
    detail: j['detail']?.toString(),
    matchedRules: (j['matchedRules'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
    acknowledgedAt: DateTime.tryParse(j['acknowledgedAt']?.toString() ?? '')?.toLocal(),
    resolvedAt: DateTime.tryParse(j['resolvedAt']?.toString() ?? '')?.toLocal(),
    resolutionNotes: j['resolutionNotes']?.toString(),
  );
}

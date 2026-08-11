// Medical prescription shorthand <-> plain language — THE single source of truth.
//
// The doctor writes/reads shorthand (OD, BD, TDS, AC, PC, HS, PRN…); the patient
// and dietician read the full phrase ("Twice a day, after food"). Both come from
// this one file, so the two can never drift, and adding a term updates every
// panel at once.

/// How often a dose is taken. The value the doctor picks.
enum DoseFrequency { od, bd, tds, qid, eod, hs, prn, stat }

extension DoseFrequencyX on DoseFrequency {
  /// The shorthand the doctor sees.
  String get code => switch (this) {
    DoseFrequency.od => 'OD',
    DoseFrequency.bd => 'BD',
    DoseFrequency.tds => 'TDS',
    DoseFrequency.qid => 'QID',
    DoseFrequency.eod => 'EOD',
    DoseFrequency.hs => 'HS',
    DoseFrequency.prn => 'PRN',
    DoseFrequency.stat => 'Stat',
  };

  /// The plain phrase the patient/dietician see.
  String get plain => switch (this) {
    DoseFrequency.od => 'Once a day',
    DoseFrequency.bd => 'Twice a day',
    DoseFrequency.tds => 'Three times a day',
    DoseFrequency.qid => 'Four times a day',
    DoseFrequency.eod => 'Every other day',
    DoseFrequency.hs => 'At bedtime',
    DoseFrequency.prn => 'As needed',
    DoseFrequency.stat => 'Immediately (single dose)',
  };

  /// The `frequency` string the API/schedule engine understands.
  String get apiFrequency => switch (this) {
    DoseFrequency.od => 'OD',
    DoseFrequency.bd => 'BD',
    DoseFrequency.tds => 'TDS',
    DoseFrequency.qid => 'QID',
    // Sent verbatim so the backend derives dayInterval=2; it schedules one
    // morning dose and the device fires it only every other day.
    DoseFrequency.eod => 'EOD',
    DoseFrequency.hs => 'HS',
    DoseFrequency.prn => 'PRN',
    DoseFrequency.stat => 'STAT',
  };

  /// Only real recurring meal-anchored doses take a before/after-meal relation.
  bool get takesMealRelation =>
      this == DoseFrequency.od ||
      this == DoseFrequency.bd ||
      this == DoseFrequency.tds ||
      this == DoseFrequency.qid ||
      this == DoseFrequency.eod;

  /// These never arm reminders (as-needed / immediate one-off).
  bool get isAsNeeded => this == DoseFrequency.prn;
  bool get isStat => this == DoseFrequency.stat;
  bool get isEveryOtherDay => this == DoseFrequency.eod;
}

/// A dose's relation to food.
enum MealRelation { anytime, before, withFood, after }

extension MealRelationX on MealRelation {
  /// The API enum value.
  String get api => switch (this) {
    MealRelation.anytime => 'any',
    MealRelation.before => 'before_meal',
    MealRelation.withFood => 'with_meal',
    MealRelation.after => 'after_meal',
  };

  /// The shorthand suffix (AC/PC); blank when there's no standard one.
  String get code => switch (this) {
    MealRelation.anytime => '',
    MealRelation.before => 'AC',
    MealRelation.withFood => '',
    MealRelation.after => 'PC',
  };

  /// The plain phrase.
  String get plain => switch (this) {
    MealRelation.anytime => '',
    MealRelation.before => 'before food',
    MealRelation.withFood => 'with food',
    MealRelation.after => 'after food',
  };

  static MealRelation fromApi(String? v) => switch (v) {
    'before_meal' => MealRelation.before,
    'with_meal' => MealRelation.withFood,
    'after_meal' => MealRelation.after,
    _ => MealRelation.anytime,
  };
}

/// The route of administration.
enum MedRoute { oral, iv, sc, im, topical, inhaled }

extension MedRouteX on MedRoute {
  String get api => name; // oral | iv | sc | im | topical | inhaled

  String get code => switch (this) {
    MedRoute.oral => 'PO',
    MedRoute.iv => 'IV',
    MedRoute.sc => 'SC',
    MedRoute.im => 'IM',
    MedRoute.topical => 'Top',
    MedRoute.inhaled => 'Inh',
  };

  String get plain => switch (this) {
    MedRoute.oral => 'by mouth',
    MedRoute.iv => 'intravenous',
    MedRoute.sc => 'subcutaneous',
    MedRoute.im => 'intramuscular',
    MedRoute.topical => 'applied to skin',
    MedRoute.inhaled => 'inhaled',
  };

  static MedRoute fromApi(String? v) =>
      MedRoute.values.firstWhere((r) => r.name == v, orElse: () => MedRoute.oral);
}

/// The doctor's composed shorthand, e.g. "BDPC", "TDS AC", "HS", "PRN", "OD PO".
String composeShorthand({
  required DoseFrequency frequency,
  MealRelation relation = MealRelation.anytime,
  MedRoute route = MedRoute.oral,
}) {
  final parts = <String>[];
  final meal = frequency.takesMealRelation ? relation.code : '';
  // Compounds like BDAC/BDPC read as one token; a bare frequency stands alone.
  parts.add(meal.isEmpty ? frequency.code : '${frequency.code}$meal');
  // Route only shown when it isn't the default oral.
  if (route != MedRoute.oral) parts.add(route.code);
  return parts.join(' ');
}

/// The patient/dietician's full phrase, e.g. "Twice a day, after food, by mouth".
String expandToPlain({
  required DoseFrequency frequency,
  MealRelation relation = MealRelation.anytime,
  MedRoute route = MedRoute.oral,
}) {
  final parts = <String>[frequency.plain];
  if (frequency.takesMealRelation && relation.plain.isNotEmpty) parts.add(relation.plain);
  if (route != MedRoute.oral) parts.add(route.plain);
  return parts.join(', ');
}

/// Reconstruct the patient-facing phrase from a stored medicine's shape — a dose
/// count (from its schedule), meal relation, route, and the as-needed / stat /
/// every-other-day flags — without needing the original enum.
String doseSummaryFrom({
  required int doseCount,
  String? relationToMeal,
  String? route,
  bool asNeeded = false,
  bool stat = false,
  bool everyOtherDay = false,
  bool atBedtime = false,
}) {
  if (asNeeded) return DoseFrequency.prn.plain;
  if (stat) return DoseFrequency.stat.plain;

  final String freqPlain;
  if (atBedtime) {
    freqPlain = DoseFrequency.hs.plain;
  } else {
    freqPlain = switch (doseCount) {
      1 => DoseFrequency.od.plain,
      2 => DoseFrequency.bd.plain,
      3 => DoseFrequency.tds.plain,
      >= 4 => DoseFrequency.qid.plain,
      _ => 'As scheduled',
    };
  }

  final parts = <String>[freqPlain];
  if (everyOtherDay) parts[0] = '${parts[0]} (every other day)';
  final meal = MealRelationX.fromApi(relationToMeal).plain;
  if (!atBedtime && meal.isNotEmpty) parts.add(meal);
  final r = MedRouteX.fromApi(route);
  if (r != MedRoute.oral) parts.add(r.plain);
  return parts.join(', ');
}

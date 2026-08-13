/// One prescription the doctor issued, as the patient sees it
/// (`GET /patients/me/prescriptions`). Read-only: the record the clinic wrote,
/// plus a link to its PDF.
class PatientPrescription {
  const PatientPrescription({
    required this.id,
    required this.referenceNo,
    required this.pdfUrl,
    this.issuedOn,
    this.doctorName,
    this.complaint,
    this.diagnosis = const [],
    this.items = const [],
    this.labTestsAdvised = const [],
    this.generalAdvice,
    this.followUpOn,
  });

  final String id;
  final String referenceNo;

  /// Server path of the generated PDF, e.g.
  /// `/api/v1/patients/:patient/prescriptions/:id/pdf`.
  final String pdfUrl;

  final DateTime? issuedOn;
  final String? doctorName;
  final String? complaint;
  final List<String> diagnosis;
  final List<PrescribedItem> items;
  final List<String> labTestsAdvised;
  final String? generalAdvice;
  final DateTime? followUpOn;

  factory PatientPrescription.fromJson(Map<String, dynamic> j) => PatientPrescription(
    id: j['id']?.toString() ?? '',
    referenceNo: j['referenceNo']?.toString() ?? '',
    pdfUrl: j['pdfUrl']?.toString() ?? '',
    issuedOn: DateTime.tryParse(j['issuedOn']?.toString() ?? '')?.toLocal(),
    doctorName: j['doctorName']?.toString(),
    complaint: j['complaint']?.toString(),
    diagnosis: (j['diagnosis'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    items: (j['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PrescribedItem.fromJson)
            .toList() ??
        const [],
    labTestsAdvised: (j['labTestsAdvised'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    generalAdvice: j['generalAdvice']?.toString(),
    followUpOn: DateTime.tryParse(j['followUpOn']?.toString() ?? '')?.toLocal(),
  );
}

/// One medicine line on a prescription.
class PrescribedItem {
  const PrescribedItem({
    required this.name,
    this.strength,
    this.dose,
    this.frequency,
    this.durationDays,
    this.relationToMeal,
    this.route,
    this.instructions,
  });

  final String name;
  final String? strength;
  final String? dose;
  final String? frequency;
  final int? durationDays;
  final String? relationToMeal;
  final String? route;
  final String? instructions;

  /// "Metformin 500mg" — name with strength when present.
  String get title => (strength == null || strength!.isEmpty) ? name : '$name $strength';

  /// The plain-English dosing line under the name.
  String get detail {
    final parts = <String>[
      if (frequency != null && frequency!.isNotEmpty) frequency!,
      if (relationToMeal != null && relationToMeal != 'any') _mealPhrase(relationToMeal!),
      if (durationDays != null) 'for $durationDays days',
    ];
    final line = parts.join(', ');
    if (instructions != null && instructions!.isNotEmpty) {
      return line.isEmpty ? instructions! : '$line · $instructions';
    }
    return line;
  }

  static String _mealPhrase(String r) => switch (r) {
    'before_meal' => 'before food',
    'after_meal' => 'after food',
    'with_meal' => 'with food',
    _ => '',
  };

  factory PrescribedItem.fromJson(Map<String, dynamic> j) => PrescribedItem(
    name: j['name']?.toString() ?? '',
    strength: j['strength']?.toString(),
    dose: j['dose']?.toString(),
    frequency: j['frequency']?.toString(),
    durationDays: (j['durationDays'] as num?)?.toInt(),
    relationToMeal: j['relationToMeal']?.toString(),
    route: j['route']?.toString(),
    instructions: j['instructions']?.toString(),
  );
}

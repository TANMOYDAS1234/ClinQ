/// A test report the patient uploaded against a doctor-advised test.
class LabResult {
  const LabResult({required this.id, required this.testName, required this.note, this.photoUrl, this.createdAt});

  final String id;
  final String testName;
  final String note;
  final String? photoUrl;
  final DateTime? createdAt;

  factory LabResult.fromJson(Map<String, dynamic> j) => LabResult(
        id: j['id']?.toString() ?? '',
        testName: j['testName']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        photoUrl: (j['photoUrl'] == null || j['photoUrl'].toString().isEmpty) ? null : j['photoUrl'].toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
      );
}

/// The tests the doctor advised + the reports the patient has uploaded.
class LabTestsView {
  const LabTestsView({required this.advised, required this.results});

  final List<String> advised;
  final List<LabResult> results;

  /// True once a report has been uploaded for [test].
  bool hasResultFor(String test) => results.any((r) => r.testName.toLowerCase() == test.toLowerCase());

  factory LabTestsView.fromJson(Map<String, dynamic> j) => LabTestsView(
        advised: (j['advised'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        results: (j['results'] as List?)?.whereType<Map<String, dynamic>>().map(LabResult.fromJson).toList() ?? const [],
      );
}

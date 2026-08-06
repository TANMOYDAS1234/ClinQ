/// A test report the patient uploaded against a doctor-advised test.
class LabResult {
  const LabResult({
    required this.id,
    required this.testName,
    required this.note,
    this.photoUrl,
    this.createdAt,
    this.mimeType,
    this.originalName,
    this.sizeBytes,
    this.analysisStatus,
    this.analysisSummary,
    this.abnormal = const [],
  });

  final String id;
  final String testName;
  final String note;
  final String? photoUrl;
  final DateTime? createdAt;

  /// The stored file's type. `photoUrl` is a historical name — the upload sheet
  /// has always accepted PDFs and Office files too, and without this the screen
  /// drew every one of them as an image and got a broken thumbnail.
  final String? mimeType;
  final String? originalName;
  final int? sizeBytes;

  /// `pending` | `done` | `failed` | `unsupported`. Sent alongside the values
  /// so a report that could not be read says so, instead of looking like a
  /// report with nothing on it.
  final String? analysisStatus;
  final String? analysisSummary;

  /// Values the report itself marked out of range.
  final List<String> abnormal;

  bool get isReading => analysisStatus == 'pending';
  bool get couldNotRead => analysisStatus == 'failed' || analysisStatus == 'unsupported';

  /// True when the report is something that can actually be shown as a picture.
  /// Unknown types are treated as documents: a file card that opens is a better
  /// wrong guess than an image box that cannot load.
  bool get isImage => mimeType?.startsWith('image/') ?? false;

  bool get hasFile => photoUrl != null && photoUrl!.isNotEmpty;

  factory LabResult.fromJson(Map<String, dynamic> j) => LabResult(
        id: j['id']?.toString() ?? '',
        testName: j['testName']?.toString() ?? '',
        note: j['note']?.toString() ?? '',
        photoUrl: (j['photoUrl'] == null || j['photoUrl'].toString().isEmpty) ? null : j['photoUrl'].toString(),
        createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal(),
        mimeType: j['mimeType']?.toString(),
        originalName: j['originalName']?.toString(),
        sizeBytes: (j['sizeBytes'] as num?)?.toInt(),
        analysisStatus: (j['analysis'] as Map<String, dynamic>?)?['status']?.toString(),
        analysisSummary: (j['analysis'] as Map<String, dynamic>?)?['summary']?.toString(),
        abnormal: ((j['analysis'] as Map<String, dynamic>?)?['abnormal'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
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

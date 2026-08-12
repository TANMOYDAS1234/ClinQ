/// The clinic's diabetes/endocrine diagnosis pick-list. The doctor selects by
/// the short code shown on the chip (T2DM, FL-2, HT…); the full [label] is what
/// gets stored on the prescription and printed on the PDF, so the patient reads
/// a clear diagnosis rather than an abbreviation.
///
/// Anything not in this list can still be added as free text in the consult.
class DiagnosisOption {
  const DiagnosisOption({required this.code, required this.label, required this.category});

  /// Short shorthand shown on the chip, e.g. `T2DM`.
  final String code;

  /// Full clinical name — what is stored and printed.
  final String label;

  /// Grouping for the sectioned picker.
  final String category;
}

const List<DiagnosisOption> kDiagnosisCatalog = [
  // Diabetes
  DiagnosisOption(code: 'T1DM', label: 'Type 1 Diabetes Mellitus', category: 'Diabetes'),
  DiagnosisOption(code: 'T2DM', label: 'Type 2 Diabetes Mellitus', category: 'Diabetes'),
  DiagnosisOption(code: 'GDM', label: 'Gestational Diabetes Mellitus', category: 'Diabetes'),
  DiagnosisOption(code: 'Pre-DM', label: 'Prediabetes', category: 'Diabetes'),

  // Liver
  DiagnosisOption(code: 'FL-1', label: 'Fatty Liver — Grade 1', category: 'Liver'),
  DiagnosisOption(code: 'FL-2', label: 'Fatty Liver — Grade 2', category: 'Liver'),
  DiagnosisOption(code: 'FL-3', label: 'Fatty Liver — Grade 3', category: 'Liver'),
  DiagnosisOption(code: 'LS', label: 'Liver Steatosis', category: 'Liver'),
  DiagnosisOption(code: 'Cirrhosis', label: 'Liver Cirrhosis', category: 'Liver'),

  // Cardiometabolic
  DiagnosisOption(code: 'HT', label: 'Hypertension', category: 'Cardiometabolic'),
  DiagnosisOption(code: 'Dyslipidaemia', label: 'Dyslipidaemia', category: 'Cardiometabolic'),
  DiagnosisOption(code: 'Obesity', label: 'Obesity', category: 'Cardiometabolic'),
  DiagnosisOption(code: 'IR', label: 'Insulin Resistance', category: 'Cardiometabolic'),

  // Complications
  DiagnosisOption(code: 'DFU', label: 'Diabetic Foot Ulcer', category: 'Complications'),
  DiagnosisOption(code: 'DR', label: 'Diabetic Retinopathy', category: 'Complications'),
  DiagnosisOption(code: 'Neuropathy', label: 'Diabetic Neuropathy', category: 'Complications'),
  DiagnosisOption(code: 'Nephropathy', label: 'Diabetic Nephropathy (CKD)', category: 'Complications'),

  // Thyroid
  DiagnosisOption(code: 'Hypothyroid', label: 'Hypothyroidism', category: 'Thyroid'),
  DiagnosisOption(code: 'Hyperthyroid', label: 'Hyperthyroidism', category: 'Thyroid'),
];

/// The options grouped by category, in catalog order — for a sectioned picker.
Map<String, List<DiagnosisOption>> diagnosisByCategory() {
  final out = <String, List<DiagnosisOption>>{};
  for (final d in kDiagnosisCatalog) {
    (out[d.category] ??= []).add(d);
  }
  return out;
}

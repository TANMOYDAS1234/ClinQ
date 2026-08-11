/// The clinic's diabetes-focused lab catalog: each ORDER is a panel (the main
/// test); its analytes are the sub-tests that come back on the report. The
/// doctor orders at the panel level — you order "Lipid Profile", not "LDL".
///
/// Panels are matched to reports and prescriptions by their [name], so this is
/// the single list every surface draws from — keep names stable.
class LabPanel {
  const LabPanel({required this.name, required this.category, this.analytes = const []});

  /// The ordered name, stored in `labTestsAdvised` and matched against reports.
  final String name;

  /// Grouping for the picker (Glycemic, Lipid, Renal…).
  final String category;

  /// The sub-tests the panel reports. Empty for a single-value test (HbA1c).
  final List<String> analytes;

  bool get isPanel => analytes.isNotEmpty;
}

const List<LabPanel> kLabCatalog = [
  // Glycemic
  LabPanel(name: 'HbA1c', category: 'Glycemic'),
  LabPanel(name: 'Fasting Blood Sugar', category: 'Glycemic'),
  LabPanel(name: 'Post-Prandial Blood Sugar', category: 'Glycemic'),
  LabPanel(name: 'Random Blood Sugar', category: 'Glycemic'),

  // Lipid
  LabPanel(
    name: 'Lipid Profile',
    category: 'Lipid',
    analytes: ['Total Cholesterol', 'LDL', 'HDL', 'VLDL', 'Triglycerides'],
  ),

  // Renal
  LabPanel(
    name: 'Kidney Function (KFT)',
    category: 'Renal',
    analytes: ['Urea', 'Creatinine', 'Uric Acid', 'eGFR', 'BUN'],
  ),
  LabPanel(
    name: 'Urine Microalbumin (ACR)',
    category: 'Renal',
    analytes: ['Microalbumin', 'Albumin/Creatinine Ratio'],
  ),

  // Liver
  LabPanel(
    name: 'Liver Function (LFT)',
    category: 'Liver',
    analytes: ['SGOT (AST)', 'SGPT (ALT)', 'ALP', 'Bilirubin', 'Albumin', 'Total Protein'],
  ),

  // Thyroid
  LabPanel(name: 'Thyroid Profile', category: 'Thyroid', analytes: ['TSH', 'T3', 'T4']),

  // Hematology
  LabPanel(
    name: 'CBC',
    category: 'Hematology',
    analytes: ['Hemoglobin', 'TLC', 'RBC', 'Platelets', 'PCV', 'MCV'],
  ),

  // Metabolic / other
  LabPanel(name: 'Serum Electrolytes', category: 'Metabolic', analytes: ['Sodium', 'Potassium', 'Chloride']),
  LabPanel(name: 'Vitamin B12', category: 'Vitamins'),
  LabPanel(name: 'Vitamin D', category: 'Vitamins'),
];

/// Case-insensitive lookup so an ordered/reported name resolves to its panel
/// (and its sub-tests) even if the wording drifts slightly.
LabPanel? labPanelFor(String name) {
  final n = name.trim().toLowerCase();
  for (final p in kLabCatalog) {
    if (p.name.toLowerCase() == n) return p;
  }
  return null;
}

/// The panels grouped by category, in catalog order — for a sectioned picker.
Map<String, List<LabPanel>> labCatalogByCategory() {
  final out = <String, List<LabPanel>>{};
  for (final p in kLabCatalog) {
    (out[p.category] ??= []).add(p);
  }
  return out;
}

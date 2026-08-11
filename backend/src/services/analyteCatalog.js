/**
 * Reference ranges for the analytes the lab extractor reads, so a stored value
 * can be turned into a general {value, range, flag} the doctor's record shows
 * uniformly — instead of eight loose fields nobody surfaces.
 *
 * Ranges are adult diabetic targets (the clinic's population), deliberately
 * simple: `low`/`high` bound the acceptable window, `null` means "no bound on
 * that side" (LDL has no lower concern; HDL has no upper one). The flag is a
 * plain comparison — no interpretation, matching the rest of the pipeline.
 */
const ANALYTES = [
  { code: 'hba1c', field: 'hba1cPercent', label: 'HbA1c', unit: '%', low: null, high: 7.0 },
  { code: 'fbs', field: 'fastingGlucoseMgDl', label: 'Fasting glucose', unit: 'mg/dL', low: 70, high: 130 },
  { code: 'ppbs', field: 'postPrandialGlucoseMgDl', label: 'Post-meal glucose', unit: 'mg/dL', low: null, high: 180 },
  { code: 'tchol', field: 'totalCholesterol', label: 'Total cholesterol', unit: 'mg/dL', low: null, high: 200 },
  { code: 'ldl', field: 'ldl', label: 'LDL', unit: 'mg/dL', low: null, high: 100 },
  { code: 'hdl', field: 'hdl', label: 'HDL', unit: 'mg/dL', low: 40, high: null },
  { code: 'tg', field: 'triglycerides', label: 'Triglycerides', unit: 'mg/dL', low: null, high: 150 },
  { code: 'creat', field: 'creatinine', label: 'Creatinine', unit: 'mg/dL', low: 0.6, high: 1.3 },
];

/** low | normal | high for a value against its reference window. */
function flagFor(value, low, high) {
  if (low != null && value < low) return 'low';
  if (high != null && value > high) return 'high';
  return 'normal';
}

/**
 * Turn a LabResult.analysis blob into a uniform list of analyte readings, each
 * with its value, unit, reference window and a low/normal/high flag. Only the
 * fields the report actually carried appear.
 */
export function buildAnalytes(analysis) {
  if (!analysis) return [];
  const out = [];
  for (const a of ANALYTES) {
    const value = analysis[a.field];
    if (value == null) continue;
    out.push({
      code: a.code,
      label: a.label,
      value,
      unit: a.unit,
      refLow: a.low,
      refHigh: a.high,
      flag: flagFor(value, a.low, a.high),
    });
  }
  return out;
}

export { ANALYTES };

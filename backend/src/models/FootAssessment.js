import mongoose from 'mongoose';

export const FOOT_SITES = Object.freeze([
  'left_dorsum',
  'left_sole',
  'left_heel',
  'left_toes',
  'right_dorsum',
  'right_sole',
  'right_heel',
  'right_toes',
]);

/**
 * Diabetic foot screening. `aiAssessment` is explicitly advisory — the schema
 * keeps the model's output separate from `clinicianReview` so a doctor's
 * verdict can never be overwritten by a later AI pass.
 */
const footAssessmentSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    // Groups repeat photos of the same wound over time so progression can be
    // charted. Generated on the first assessment of a wound.
    woundKey: { type: String, index: true },
    site: { type: String, enum: FOOT_SITES, required: true },

    images: [{ type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' }],
    assessedAt: { type: Date, default: Date.now, index: true },

    // Patient-reported symptoms feed the deterministic risk rules.
    symptoms: {
      pain: { type: String, enum: ['none', 'mild', 'moderate', 'severe'], default: 'none' },
      numbness: { type: Boolean, default: false },
      discharge: { type: Boolean, default: false },
      foulSmell: { type: Boolean, default: false },
      swelling: { type: Boolean, default: false },
      blackTissue: { type: Boolean, default: false },
      fever: { type: Boolean, default: false },
      durationDays: { type: Number, min: 0, max: 3650 },
    },

    aiAssessment: {
      riskLevel: { type: String, enum: ['low', 'moderate', 'high', 'urgent'] },
      wagnerGradeEstimate: { type: Number, min: 0, max: 5 },
      observations: { type: String, maxlength: 3000 },
      recommendations: { type: String, maxlength: 3000 },
      confidence: { type: String, enum: ['low', 'medium', 'high'] },
      modelVersion: String,
      generatedAt: Date,
    },

    // Deterministic rules run alongside the model; the higher of the two risk
    // levels is what the patient is shown.
    ruleRiskLevel: { type: String, enum: ['low', 'moderate', 'high', 'urgent'], index: true },
    finalRiskLevel: { type: String, enum: ['low', 'moderate', 'high', 'urgent'], index: true },

    clinicianReview: {
      reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
      reviewedAt: Date,
      riskLevel: { type: String, enum: ['low', 'moderate', 'high', 'urgent'] },
      notes: { type: String, maxlength: 3000 },
    },

    followUpDueOn: Date,
    alert: { type: mongoose.Schema.Types.ObjectId, ref: 'ClinicalAlert' },
  },
  { timestamps: true },
);

footAssessmentSchema.index({ patient: 1, assessedAt: -1 });

export const FootAssessment = mongoose.model('FootAssessment', footAssessmentSchema);

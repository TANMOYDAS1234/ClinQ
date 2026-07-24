import mongoose from 'mongoose';

export const DR_GRADES = Object.freeze([
  'no_dr',
  'mild_npdr',
  'moderate_npdr',
  'severe_npdr',
  'pdr',
  'unknown',
]);

/**
 * Retinal / ophthalmology report. The AI here explains an existing report in
 * plain language — it does not grade retinopathy from a fundus image, which
 * would require a validated diagnostic device.
 */
const eyeReportSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    reportDate: { type: Date, required: true, index: true },
    files: [{ type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' }],

    // Transcribed from the report by the patient or extracted by the model.
    reportedGrade: { type: String, enum: DR_GRADES, default: 'unknown' },
    hasMacularOedema: { type: Boolean, default: false },
    examinedBy: { type: String, trim: true, maxlength: 160 },
    rawReportText: { type: String, maxlength: 20000 },

    visualAcuity: {
      leftEye: { type: String, trim: true, maxlength: 20 },
      rightEye: { type: String, trim: true, maxlength: 20 },
    },

    aiExplanation: {
      summary: { type: String, maxlength: 4000 },
      whatItMeans: { type: String, maxlength: 4000 },
      recommendedActions: { type: String, maxlength: 3000 },
      referralUrgency: { type: String, enum: ['routine', 'soon', 'urgent'] },
      language: { type: String, enum: ['en', 'bn', 'hi'], default: 'en' },
      modelVersion: String,
      generatedAt: Date,
    },

    clinicianReview: {
      reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
      reviewedAt: Date,
      notes: { type: String, maxlength: 3000 },
    },

    nextScreeningDueOn: Date,
  },
  { timestamps: true },
);

eyeReportSchema.index({ patient: 1, reportDate: -1 });

export const EyeReport = mongoose.model('EyeReport', eyeReportSchema);

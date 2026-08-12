import mongoose from 'mongoose';

/**
 * A prescription is an immutable clinical record. Corrections create a new
 * version pointing at `supersedes` rather than mutating the original — an
 * edited prescription with no history is a compliance problem.
 */
const prescriptionSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    appointment: { type: mongoose.Schema.Types.ObjectId, ref: 'Appointment' },

    // Human-readable, printed on the PDF. e.g. "AKD-2026-000412"
    referenceNo: { type: String, required: true, unique: true },
    issuedOn: { type: Date, required: true, default: Date.now, index: true },
    validUntil: Date,

    // The presenting complaint at this visit, snapshotted so the printed
    // prescription reflects what was said that day even as the patient's
    // current complaint on their profile moves on.
    complaint: { type: String, trim: true, maxlength: 1000 },

    diagnosis: [{ type: String, trim: true, maxlength: 300 }],
    items: [
      {
        name: { type: String, required: true, trim: true, maxlength: 160 },
        strength: { type: String, trim: true, maxlength: 60 },
        dose: { type: String, trim: true, maxlength: 60 },
        frequency: { type: String, trim: true, maxlength: 120 }, // "1-0-1"
        durationDays: { type: Number, min: 1, max: 365 },
        relationToMeal: {
          type: String,
          enum: ['before_meal', 'after_meal', 'with_meal', 'any'],
          default: 'any',
        },
        instructions: { type: String, maxlength: 400 },
      },
    ],

    labTestsAdvised: [{ type: String, trim: true, maxlength: 200 }],
    generalAdvice: { type: String, maxlength: 4000 },
    followUpOn: Date,

    pdfFile: { type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' },

    supersedes: { type: mongoose.Schema.Types.ObjectId, ref: 'Prescription' },
    isActive: { type: Boolean, default: true, index: true },
  },
  { timestamps: true },
);

prescriptionSchema.index({ patient: 1, issuedOn: -1 });

export const Prescription = mongoose.model('Prescription', prescriptionSchema);

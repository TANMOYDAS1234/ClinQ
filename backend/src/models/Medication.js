import mongoose from 'mongoose';

export const MED_FORMS = Object.freeze([
  'tablet',
  'capsule',
  'insulin',
  'injection',
  'syrup',
  'inhaler',
  'topical',
  'other',
]);

/**
 * A medication the patient is currently expected to take. Insulin is modelled
 * here too (form: 'insulin') so adherence and dose logging share one pipeline.
 */
const medicationSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    name: { type: String, required: true, trim: true, maxlength: 160 },
    genericName: { type: String, trim: true, maxlength: 160 },
    form: { type: String, enum: MED_FORMS, default: 'tablet' },

    strength: { type: String, trim: true, maxlength: 60 }, // e.g. "500 mg", "100 IU/mL"
    dose: { type: String, trim: true, maxlength: 60 }, // e.g. "1 tablet", "12 units"

    // Local clock times "HH:mm" — reminders are scheduled on the device, so the
    // server stays timezone-agnostic.
    schedule: [
      {
        time: { type: String, required: true, match: [/^([01]\d|2[0-3]):[0-5]\d$/, 'time must be HH:mm'] },
        relationToMeal: {
          type: String,
          enum: ['before_meal', 'after_meal', 'with_meal', 'any'],
          default: 'any',
        },
      },
    ],
    daysOfWeek: {
      // 0 = Sunday. Empty means every day.
      type: [Number],
      default: [],
      validate: [(v) => v.every((d) => d >= 0 && d <= 6), 'daysOfWeek must be 0-6'],
    },

    startDate: { type: Date, default: Date.now },
    endDate: Date,
    isActive: { type: Boolean, default: true, index: true },

    prescribedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    prescription: { type: mongoose.Schema.Types.ObjectId, ref: 'Prescription' },
    instructions: { type: String, maxlength: 600 },
  },
  { timestamps: true },
);

medicationSchema.index({ patient: 1, isActive: 1 });

export const Medication = mongoose.model('Medication', medicationSchema);

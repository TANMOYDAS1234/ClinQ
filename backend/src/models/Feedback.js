import mongoose from 'mongoose';

/**
 * A patient's feedback about the app or about the clinic.
 *
 * Kept apart from ClinicalAlert and the care thread on purpose. Feedback is not
 * a clinical event: routing "the app is slow" into the same queue as a chest-pain
 * escalation would either bury the alert or train the clinic to skim the queue.
 *
 * Never anonymous internally — the clinic can follow up on a complaint about
 * care, and a patient who says treatment went wrong deserves a reply rather than
 * a suggestion box. Whether the patient is *told* it is attributable is a copy
 * decision on the form.
 */
const feedbackSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    /// What is being rated. Separated because they are acted on by different
    /// people: `app` is a product issue, `clinic` is the doctor's to answer.
    about: { type: String, enum: ['app', 'clinic'], required: true, index: true },

    /// 1–5. Optional: someone with a specific complaint should not be forced to
    /// reduce it to a number before they can send it.
    rating: { type: Number, min: 1, max: 5 },

    message: { type: String, trim: true, maxlength: 2000 },

    /// Set once a clinician has read it, so the clinic can see what is new
    /// without a second collection tracking state.
    reviewedAt: { type: Date },
    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);

feedbackSchema.index({ createdAt: -1 });

export const Feedback = mongoose.model('Feedback', feedbackSchema);

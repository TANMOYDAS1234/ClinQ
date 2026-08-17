import mongoose from 'mongoose';

/**
 * A diet plan as it stood when it was replaced.
 *
 * `DietPlan` holds exactly one document per patient and is edited in place, on
 * purpose: the patient needs one current answer to "what do I eat", and two
 * live plans would be two answers. That invariant is worth keeping, so this
 * gives the dietician history without breaking it — when they start a fresh
 * plan, the outgoing one is copied here and the current document is rewritten.
 *
 * Nothing patient-facing reads this collection. It exists so the dietician can
 * see what they had the patient on before, which is the question they actually
 * ask when a target has not been met: what were we doing, and for how long.
 */
const revisionMealSchema = new mongoose.Schema(
  {
    name: { type: String, trim: true, maxlength: 60 },
    time: { type: String, trim: true, maxlength: 20 },
    items: [{ type: String, trim: true, maxlength: 300 }],
    notes: { type: String, trim: true, maxlength: 500 },
  },
  { _id: false },
);

const dietPlanRevisionSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    /// Who wrote the plan being archived, not who archived it. The history is a
    /// record of care given, and attributing an old plan to whoever happened to
    /// replace it would misreport who advised the patient.
    dietician: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },

    goal: { type: String, trim: true, maxlength: 300 },
    meals: [revisionMealSchema],
    avoid: [{ type: String, trim: true, maxlength: 120 }],
    notes: { type: String, trim: true, maxlength: 2000 },

    /// When the patient was actually given this plan. Null means it never left
    /// the dietician's screen, which matters: a plan the patient never saw is
    /// not care that was delivered.
    sharedAt: { type: Date },

    /// When it stopped being the current plan.
    replacedAt: { type: Date, default: Date.now, index: true },

    /// When the archived plan was first written, carried over so the history
    /// can show how long the patient was on it.
    startedAt: { type: Date },
  },
  { timestamps: true },
);

dietPlanRevisionSchema.index({ patient: 1, replacedAt: -1 });

export const DietPlanRevision = mongoose.model('DietPlanRevision', dietPlanRevisionSchema);

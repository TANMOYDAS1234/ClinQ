import mongoose from 'mongoose';

/**
 * The structured diet plan a dietician writes for one patient.
 *
 * Chat guidance is easy to write and easy to lose — three weeks and two hundred
 * messages later, "so what am I supposed to eat at breakfast?" has no answer the
 * patient can find. A plan is the durable form of the same advice: one document
 * per patient, edited in place, always current.
 *
 * Never auto-generated. The assistant may explain a plan the dietician wrote; it
 * may not write one. Prescribing what a diabetic eats is a clinical act.
 */
const mealSchema = new mongoose.Schema(
  {
    /// Free text rather than an enum: an Indian day is not breakfast/lunch/dinner.
    /// "Mid-morning", "tiffin", "before namaz" all need to be sayable.
    name: { type: String, trim: true, required: true, maxlength: 60 },

    /// "8:00 am", "within 30 min of insulin" — a string, because the useful
    /// answer is often relative to something rather than a clock time.
    time: { type: String, trim: true, maxlength: 40 },

    /// One line per item, so the patient reads a list and not a paragraph.
    items: { type: [String], default: [] },

    notes: { type: String, trim: true, maxlength: 500 },
  },
  { _id: false },
);

const dietPlanSchema = new mongoose.Schema(
  {
    /// One live plan per patient. A second plan would mean two answers to
    /// "what do I eat", which is worse than none.
    patient: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true,
      unique: true,
      index: true,
    },

    /// Who wrote the current version. Attribution matters: the patient is
    /// following instructions and is entitled to know whose they are.
    dietician: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },

    /// What this plan is for, in the patient's terms — "bring fasting sugar
    /// under 130 without cutting rice completely".
    goal: { type: String, trim: true, maxlength: 500 },

    meals: { type: [mealSchema], default: [] },

    /// Kept separate from the meals rather than repeated under each one. A
    /// patient scanning for "can I have this?" should have one place to look.
    avoid: { type: [String], default: [] },

    notes: { type: String, trim: true, maxlength: 2000 },

    /// When the plan was last pushed into the care thread. A plan the patient
    /// has never been shown is a draft, however finished it looks.
    sharedAt: { type: Date },
  },
  { timestamps: true },
);

export const DietPlan = mongoose.model('DietPlan', dietPlanSchema);

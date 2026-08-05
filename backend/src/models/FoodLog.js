import mongoose from 'mongoose';

export const MEAL_TYPES = Object.freeze(['breakfast', 'lunch', 'dinner', 'snack', 'other']);

/**
 * A meal the patient logged for their dietician to review. A photo is optional
 * (a MediaAsset served from /uploads/:id/raw); a note describes what they ate.
 */
const foodLogSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    mealType: { type: String, enum: MEAL_TYPES, default: 'other' },
    note: { type: String, trim: true, maxlength: 1000 },
    photo: { type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' },

    /// The chat message this arrived in, when the patient sent it to their
    /// dietician rather than logging it from the food screen. Logging a meal
    /// and showing it to the dietician are the same act, so they produce one
    /// record — this is the link back to the conversation it came from.
    sourceMessage: { type: mongoose.Schema.Types.ObjectId, ref: 'ChatMessage' },
  },
  { timestamps: true },
);

foodLogSchema.index({ patient: 1, createdAt: -1 });

export const FoodLog = mongoose.model('FoodLog', foodLogSchema);

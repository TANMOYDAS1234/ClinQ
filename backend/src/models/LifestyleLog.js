import mongoose from 'mongoose';

export const LIFESTYLE_KINDS = Object.freeze(['meal', 'exercise', 'water', 'sleep']);

/**
 * A single collection for diet / exercise / water / sleep. They share the same
 * "many small entries per day, aggregated for the dashboard" access pattern, and
 * one collection keeps the daily-summary aggregation to a single pipeline.
 */
const lifestyleLogSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    kind: { type: String, enum: LIFESTYLE_KINDS, required: true, index: true },
    loggedAt: { type: Date, required: true, default: Date.now, index: true },

    // --- meal ---
    mealType: { type: String, enum: ['breakfast', 'lunch', 'dinner', 'snack'] },
    foodItems: [
      {
        name: { type: String, trim: true, maxlength: 160 },
        quantity: { type: String, trim: true, maxlength: 60 },
        carbsGrams: { type: Number, min: 0, max: 1000 },
        calories: { type: Number, min: 0, max: 5000 },
      },
    ],
    totalCarbsGrams: { type: Number, min: 0, max: 2000 },
    totalCalories: { type: Number, min: 0, max: 10000 },
    // Populated by the Gemini meal-analysis endpoint when a photo/description
    // is submitted; always advisory, never used for dosing.
    aiEstimated: { type: Boolean, default: false },

    // --- exercise ---
    activityType: {
      type: String,
      enum: ['walking', 'running', 'cycling', 'yoga', 'gym', 'swimming', 'household', 'other'],
    },
    durationMinutes: { type: Number, min: 0, max: 1440 },
    intensity: { type: String, enum: ['light', 'moderate', 'vigorous'] },
    steps: { type: Number, min: 0, max: 200000 },
    caloriesBurned: { type: Number, min: 0, max: 10000 },

    // --- water ---
    volumeMl: { type: Number, min: 0, max: 10000 },

    // --- sleep ---
    sleepHours: { type: Number, min: 0, max: 24 },
    sleepQuality: { type: String, enum: ['poor', 'fair', 'good'] },

    notes: { type: String, maxlength: 500 },
  },
  { timestamps: true },
);

lifestyleLogSchema.index({ patient: 1, kind: 1, loggedAt: -1 });

export const LifestyleLog = mongoose.model('LifestyleLog', lifestyleLogSchema);

import mongoose from 'mongoose';

/**
 * A patient asking to be told if a slot opens on a day that is currently full.
 *
 * Deliberately opt-in. Announcing a freed slot to every patient would bury the
 * one channel this app uses for emergencies — DKA, severe hypoglycaemia, chest
 * pain — under offers nobody asked for, and a patient who mutes the app to stop
 * those also stops the alert that matters. So only patients who actively said
 * "tell me" are ever notified, which keeps the group small and every message
 * wanted.
 */
const appointmentWaitlistSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    clinic: { type: mongoose.Schema.Types.ObjectId, ref: 'Clinic', required: true },

    /// The day the patient wants, stored at local midnight so a whole-day match
    /// is a simple equality test rather than a range scan.
    desiredDate: { type: Date, required: true },

    /// Cleared once they book, so a filled request stops competing for slots.
    isActive: { type: Boolean, default: true },

    /// Last time this entry was told about a free slot. Kept so a flapping
    /// cancel/rebook cannot notify the same person repeatedly in a few minutes.
    lastNotifiedAt: { type: Date },
  },
  { timestamps: true },
);

// One live request per patient per clinic per day.
appointmentWaitlistSchema.index(
  { patient: 1, clinic: 1, desiredDate: 1 },
  { unique: true, partialFilterExpression: { isActive: true } },
);
appointmentWaitlistSchema.index({ clinic: 1, desiredDate: 1, isActive: 1 });

export const AppointmentWaitlist = mongoose.model('AppointmentWaitlist', appointmentWaitlistSchema);

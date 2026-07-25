import mongoose from 'mongoose';

/**
 * A human-to-human message between a patient and the clinic (doctor or staff),
 * distinct from the AI assistant chat (ChatMessage). One flat thread per
 * patient — every message carries the patient it belongs to, so the patient's
 * inbox and each clinician's view are the same ordered conversation.
 */
const directMessageSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    sender: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    // Who sent it, so the UI can align the bubble and label it ("Dr. Dey").
    senderRole: { type: String, enum: ['patient', 'doctor', 'staff'], required: true },

    content: { type: String, required: true, trim: true, maxlength: 4000 },

    // Read receipts, one per side, so each can show an unread badge.
    readByPatient: { type: Boolean, default: false },
    readByClinician: { type: Boolean, default: false },
  },
  { timestamps: true },
);

directMessageSchema.index({ patient: 1, createdAt: 1 });

export const DirectMessage = mongoose.model('DirectMessage', directMessageSchema);

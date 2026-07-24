import mongoose from 'mongoose';

const chatSessionSchema = new mongoose.Schema(
  {
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    title: { type: String, trim: true, maxlength: 200, default: 'New conversation' },
    language: { type: String, enum: ['en', 'bn', 'hi'], default: 'en' },

    // Rolling summary of older turns, so long conversations stay in context
    // without resending the entire history to the model each turn.
    runningSummary: { type: String, maxlength: 6000 },
    summarisedUpToSeq: { type: Number, default: 0 },
    messageCount: { type: Number, default: 0 },

    highestUrgency: {
      type: String,
      enum: ['routine', 'advice', 'urgent', 'emergency'],
      default: 'routine',
      index: true,
    },
    lastMessageAt: { type: Date, default: Date.now, index: true },

    // Set when a doctor or staff member opens this thread for review.
    flaggedForReview: { type: Boolean, default: false, index: true },
    reviewedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    reviewedAt: Date,

    isArchived: { type: Boolean, default: false },
  },
  { timestamps: true },
);

chatSessionSchema.index({ patient: 1, lastMessageAt: -1 });

export const ChatSession = mongoose.model('ChatSession', chatSessionSchema);

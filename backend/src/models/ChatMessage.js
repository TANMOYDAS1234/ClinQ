import mongoose from 'mongoose';

const chatMessageSchema = new mongoose.Schema(
  {
    session: { type: mongoose.Schema.Types.ObjectId, ref: 'ChatSession', required: true, index: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },

    seq: { type: Number, required: true },
    role: { type: String, enum: ['user', 'assistant', 'system', 'clinician'], required: true },

    // Set only on `clinician` turns: which clinician wrote it, so the patient
    // reads "Dr. Amit Kumar Dey" rather than an anonymous clinic voice, and an
    // audit can attribute clinical advice to a named person.
    sender: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },

    content: { type: String, required: true, maxlength: 20000 },
    language: { type: String, enum: ['en', 'bn', 'hi'], default: 'en' },

    attachments: [{ type: mongoose.Schema.Types.ObjectId, ref: 'MediaAsset' }],

    // --- assistant-turn metadata ---
    triage: {
      urgency: { type: String, enum: ['routine', 'advice', 'urgent', 'emergency'] },
      matchedRules: [{ type: String }],
      redFlags: [{ type: String }],
      // True when deterministic rules fired, i.e. the verdict did not depend on
      // the model's judgement.
      ruleDriven: { type: Boolean, default: false },
    },
    // Knowledge-base chunks that grounded this answer — shown to the doctor
    // during chat review so an answer can be traced to approved content.
    citations: [
      {
        chunk: { type: mongoose.Schema.Types.ObjectId, ref: 'KnowledgeChunk' },
        title: String,
        score: Number,
      },
    ],
    modelVersion: String,
    latencyMs: Number,
    tokenUsage: {
      promptTokens: Number,
      responseTokens: Number,
    },

    // Set when the answer was produced by the safe fallback path (model error,
    // safety block, or no grounding found).
    isFallback: { type: Boolean, default: false },

    alert: { type: mongoose.Schema.Types.ObjectId, ref: 'ClinicalAlert' },
    flaggedByPatient: { type: Boolean, default: false },
  },
  { timestamps: true },
);

chatMessageSchema.index({ session: 1, seq: 1 }, { unique: true });

export const ChatMessage = mongoose.model('ChatMessage', chatMessageSchema);

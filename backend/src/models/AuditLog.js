import mongoose from 'mongoose';

/**
 * Who looked at, or changed, which patient's record. Required for healthcare
 * compliance and the only way to answer "who saw this" after the fact.
 * Append-only: no update or delete path exists in the application.
 */
const auditLogSchema = new mongoose.Schema(
  {
    actor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
    actorRole: { type: String },
    action: { type: String, required: true, index: true }, // 'read', 'create', 'update', 'export', 'login'
    resource: { type: String, required: true }, // 'GlucoseReading', 'Prescription', ...
    resourceId: { type: mongoose.Schema.Types.ObjectId },
    subjectPatient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },

    ip: String,
    userAgent: { type: String, maxlength: 300 },
    // Never store request bodies here — this is metadata only, no PHI.
    meta: { type: mongoose.Schema.Types.Mixed },

    at: { type: Date, default: Date.now, index: true },
  },
  { timestamps: false },
);

auditLogSchema.index({ subjectPatient: 1, at: -1 });

export const AuditLog = mongoose.model('AuditLog', auditLogSchema);

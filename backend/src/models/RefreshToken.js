import mongoose from 'mongoose';
import crypto from 'node:crypto';

/**
 * Refresh tokens are stored hashed so a database leak cannot be replayed as a
 * login. Rotation is enforced: using a token marks it consumed and issues a new
 * one; reuse of a consumed token revokes the whole family.
 */
const refreshTokenSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    tokenHash: { type: String, required: true, unique: true },
    familyId: { type: String, required: true, index: true },

    expiresAt: { type: Date, required: true },
    consumedAt: Date,
    revokedAt: Date,
    revokedReason: { type: String, maxlength: 200 },

    userAgent: { type: String, maxlength: 300 },
    ip: { type: String, maxlength: 60 },
  },
  { timestamps: true },
);

// Let Mongo reap expired documents rather than accumulating dead rows.
refreshTokenSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export function hashToken(raw) {
  return crypto.createHash('sha256').update(raw).digest('hex');
}

export const RefreshToken = mongoose.model('RefreshToken', refreshTokenSchema);

import jwt from 'jsonwebtoken';
import crypto from 'node:crypto';
import { env } from '../config/env.js';
import { RefreshToken, hashToken } from '../models/RefreshToken.js';
import { unauthorized } from '../middleware/errors.js';
import { logger } from '../config/logger.js';

function ttlToMs(ttl) {
  const m = /^(\d+)([smhd])$/.exec(ttl);
  if (!m) throw new Error(`invalid TTL: ${ttl}`);
  const mult = { s: 1000, m: 60_000, h: 3_600_000, d: 86_400_000 }[m[2]];
  return Number(m[1]) * mult;
}

export function signAccessToken(user) {
  return jwt.sign(
    { sub: user._id.toString(), role: user.role, name: user.name },
    env.JWT_ACCESS_SECRET,
    { expiresIn: env.ACCESS_TOKEN_TTL, issuer: 'akd-care' },
  );
}

export function verifyAccessToken(token) {
  try {
    return jwt.verify(token, env.JWT_ACCESS_SECRET, { issuer: 'akd-care' });
  } catch {
    throw unauthorized('Session expired. Please sign in again.');
  }
}

export async function issueRefreshToken(user, { familyId, req } = {}) {
  const raw = crypto.randomBytes(48).toString('base64url');
  await RefreshToken.create({
    user: user._id,
    tokenHash: hashToken(raw),
    familyId: familyId ?? crypto.randomUUID(),
    expiresAt: new Date(Date.now() + ttlToMs(env.REFRESH_TOKEN_TTL)),
    userAgent: req?.get('user-agent')?.slice(0, 300),
    ip: req?.ip,
  });
  return raw;
}

/**
 * Rotates a refresh token. If a token that was already consumed is presented
 * again, we treat it as theft and revoke the entire family — the legitimate
 * device will simply be asked to sign in again, which is the safe outcome.
 */
export async function rotateRefreshToken(rawToken, req) {
  const record = await RefreshToken.findOne({ tokenHash: hashToken(rawToken) });
  if (!record) throw unauthorized('Invalid session. Please sign in again.');

  if (record.consumedAt || record.revokedAt) {
    logger.warn({ user: record.user, familyId: record.familyId }, 'refresh token reuse detected');
    await RefreshToken.updateMany(
      { familyId: record.familyId, revokedAt: null },
      { revokedAt: new Date(), revokedReason: 'token_reuse_detected' },
    );
    throw unauthorized('Session is no longer valid. Please sign in again.');
  }

  if (record.expiresAt < new Date()) {
    throw unauthorized('Session expired. Please sign in again.');
  }

  record.consumedAt = new Date();
  await record.save();
  return record;
}

export async function revokeAllForUser(userId, reason = 'logout_all') {
  await RefreshToken.updateMany(
    { user: userId, revokedAt: null },
    { revokedAt: new Date(), revokedReason: reason },
  );
}

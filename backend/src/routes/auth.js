import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { User, ROLES, LANGUAGES } from '../models/User.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { signAccessToken, issueRefreshToken, rotateRefreshToken, revokeAllForUser } from '../services/tokens.js';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler, unauthorized, conflict } from '../middleware/errors.js';
import { AuditLog } from '../models/AuditLog.js';
import { logger } from '../config/logger.js';
import { env } from '../config/env.js';
import { Medication } from '../models/Medication.js';
import { recomputeSchedule } from '../services/medicationSchedule.js';
import { toE164 } from '../utils/phone.js';

const router = Router();

// Credential endpoints are the one place brute force actually pays off.
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 12,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { error: { code: 'RATE_LIMITED', message: 'Too many attempts. Please try again in a few minutes.' } },
});

// Normalised to E.164 before it is validated, so a number typed as ten bare
// digits registers and logs in as the same account as one typed with +91.
// Without this the two are different strings, and the lookup is exact.
const phoneSchema = z
  .string()
  .trim()
  .transform(toE164)
  .pipe(z.string().regex(/^\+?[1-9]\d{7,14}$/, 'Enter a valid phone number'));

const registerSchema = z.object({
  name: z.string().trim().min(2).max(120),
  phone: phoneSchema,
  password: z.string().min(8, 'Password must be at least 8 characters').max(128),
  email: z.string().email().optional(),
  language: z.enum(LANGUAGES).default('en'),
  dateOfBirth: z.coerce.date().optional(),
  gender: z.enum(['male', 'female', 'other', 'undisclosed']).default('undisclosed'),
  diabetesType: z.enum(['type1', 'type2', 'gestational', 'prediabetes', 'none']).default('type2'),
  // A dietician onboarding code turns this sign-up into a dietician account
  // instead of a patient. Anything else (or empty) registers a patient.
  inviteCode: z.string().trim().max(64).optional(),
});

router.post(
  '/register',
  authLimiter,
  validate({ body: registerSchema }),
  asyncHandler(async (req, res) => {
    const { name, phone, password, email, language, dateOfBirth, gender, diabetesType, inviteCode } = req.body;

    if (await User.exists({ phone })) {
      throw conflict('An account with this phone number already exists');
    }

    // Public sign-up is a patient by default; the private dietician code is the
    // only way to self-register a non-patient account.
    const isDietician = Boolean(inviteCode) && inviteCode === env.DIETICIAN_INVITE_CODE;
    const role = isDietician ? ROLES.DIETICIAN : ROLES.PATIENT;

    const user = new User({
      name,
      phone,
      email,
      language,
      dateOfBirth,
      gender,
      role,
      consent: {
        termsAcceptedAt: new Date(),
        dataProcessingAcceptedAt: new Date(),
        aiDisclaimerAcceptedAt: new Date(),
      },
    });
    await user.setPassword(password);
    await user.save();

    // Only patients get a clinical profile; a dietician has no diabetes record.
    if (!isDietician) {
      const doctor = await User.findOne({ role: ROLES.DOCTOR }).select('_id').lean();
      await PatientProfile.create({
        user: user._id,
        diabetesType,
        assignedDoctor: doctor?._id,
      });
    }

    const accessToken = signAccessToken(user);
    const refreshToken = await issueRefreshToken(user, { req });

    AuditLog.create({ actor: user._id, actorRole: user.role, action: 'register', resource: 'User', resourceId: user._id, ip: req.ip }).catch(() => {});

    res.status(201).json({ user: user.toPublic(), accessToken, refreshToken });
  }),
);

router.post(
  '/login',
  authLimiter,
  validate({ body: z.object({ phone: phoneSchema, password: z.string().min(1) }) }),
  asyncHandler(async (req, res) => {
    const { phone, password } = req.body;

    const user = await User.findOne({ phone }).select('+passwordHash');
    // Same error either way — a different message for "no such user" tells an
    // attacker which numbers are registered patients.
    if (!user || !user.isActive || !(await user.verifyPassword(password))) {
      logger.warn({ phone: `***${phone.slice(-4)}` }, 'failed login attempt');
      throw unauthorized('Incorrect phone number or password');
    }

    user.lastLoginAt = new Date();
    await user.save();

    const accessToken = signAccessToken(user);
    const refreshToken = await issueRefreshToken(user, { req });

    AuditLog.create({ actor: user._id, actorRole: user.role, action: 'login', resource: 'User', resourceId: user._id, ip: req.ip }).catch(() => {});

    res.json({ user: user.toPublic(), accessToken, refreshToken });
  }),
);

router.post(
  '/refresh',
  validate({ body: z.object({ refreshToken: z.string().min(10) }) }),
  asyncHandler(async (req, res) => {
    const record = await rotateRefreshToken(req.body.refreshToken, req);
    const user = await User.findById(record.user);
    if (!user || !user.isActive) throw unauthorized('Account is inactive');

    const accessToken = signAccessToken(user);
    const refreshToken = await issueRefreshToken(user, { familyId: record.familyId, req });

    res.json({ accessToken, refreshToken });
  }),
);

router.post(
  '/logout',
  requireAuth,
  asyncHandler(async (req, res) => {
    await revokeAllForUser(req.user._id, 'logout');
    res.status(204).end();
  }),
);

router.post(
  '/device-token',
  requireAuth,
  validate({ body: z.object({ token: z.string().min(10).max(500) }) }),
  asyncHandler(async (req, res) => {
    // A device belongs to whoever signed in on it LAST. Detach this token from
    // every OTHER account first, then attach it here — so a shared phone (or one
    // person testing both the patient and doctor roles) never keeps receiving a
    // previous user's notifications.
    await User.updateMany(
      { _id: { $ne: req.user._id }, deviceTokens: req.body.token },
      { $pull: { deviceTokens: req.body.token } },
    );
    await User.updateOne({ _id: req.user._id }, { $addToSet: { deviceTokens: req.body.token } });
    res.status(204).end();
  }),
);

// No requireAuth on purpose: sign-out clears the session BEFORE this fires, so a
// requireAuth version 401s and the token lingers on the account — the exact bug
// that made a signed-out/next user keep getting the previous user's pushes.
// Unregistering a device by its own token is safe, so remove it from everyone.
router.delete(
  '/device-token',
  validate({ body: z.object({ token: z.string().min(10).max(500) }) }),
  asyncHandler(async (req, res) => {
    await User.updateMany({ deviceTokens: req.body.token }, { $pull: { deviceTokens: req.body.token } });
    res.status(204).end();
  }),
);

router.get(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    const profile =
      req.user.role === ROLES.PATIENT ? await PatientProfile.findOne({ user: req.user._id }).lean() : null;
    res.json({ user: req.user.toPublic(), profile });
  }),
);

router.patch(
  '/me',
  requireAuth,
  validate({
    body: z.object({
      name: z.string().trim().min(2).max(120).optional(),
      email: z.string().email().optional(),
      language: z.enum(LANGUAGES).optional(),
      dateOfBirth: z.coerce.date().optional(),
      gender: z.enum(['male', 'female', 'other', 'undisclosed']).optional(),
      avatarAssetId: z.string().optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    Object.assign(req.user, req.body);
    await req.user.save();
    res.json({ user: req.user.toPublic() });
  }),
);

/**
 * Delete (deactivate) the signed-in user's own account.
 *
 * Deactivates rather than physically erasing: a clinic record must not silently
 * vanish, and both login and every patient/overview listing already exclude
 * inactive accounts — so the account disappears from the app and can no longer
 * sign in. (This is also what removes a throwaway/test account from the clinic.)
 */
router.delete(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    req.user.isActive = false;
    await req.user.save();
    res.status(204).end();
  }),
);

router.patch(
  '/me/profile',
  requireAuth,
  validate({
    body: z.object({
      heightCm: z.number().min(50).max(250).optional(),
      diabetesType: z.enum(['type1', 'type2', 'gestational', 'prediabetes', 'none']).optional(),
      diagnosedOn: z.coerce.date().optional(),
      allergies: z.array(z.string().max(120)).max(30).optional(),
      emergencyContact: z
        .object({ name: z.string().max(120), phone: z.string().max(20), relation: z.string().max(60) })
        .partial()
        .optional(),
      targets: z
        .object({
          fastingMin: z.number().min(50).max(200),
          fastingMax: z.number().min(60).max(250),
          postPrandialMax: z.number().min(80).max(300),
          hba1cMax: z.number().min(5).max(12),
        })
        .partial()
        .optional(),
      mealTimes: z
        .object({
          breakfast: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
          lunch: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
          dinner: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/),
        })
        .partial()
        .optional(),
    }),
  }),
  asyncHandler(async (req, res) => {
    const profile = await PatientProfile.findOneAndUpdate(
      { user: req.user._id },
      { $set: flattenForUpdate(req.body) },
      { new: true, upsert: true },
    ).lean();

    // When meal times change, re-derive reminder times for every active medicine
    // the patient has NOT hand-overridden, so "before breakfast" tracks the new
    // breakfast time automatically.
    if (req.body.mealTimes) {
      const meds = await Medication.find({ patient: req.user._id, isActive: true, timesCustomized: { $ne: true } });
      for (const med of meds) {
        med.schedule = recomputeSchedule(med.schedule, profile.mealTimes);
        await med.save();
      }
    }

    res.json({ profile });
  }),
);

/** Dot-notation so a partial `targets` patch does not wipe unsent sibling keys. */
function flattenForUpdate(obj, prefix = '') {
  const out = {};
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === 'object' && !Array.isArray(v) && !(v instanceof Date)) {
      Object.assign(out, flattenForUpdate(v, key));
    } else {
      out[key] = v;
    }
  }
  return out;
}

export default router;

import { verifyAccessToken } from '../services/tokens.js';
import { User, ROLES } from '../models/User.js';
import { unauthorized, forbidden, asyncHandler } from './errors.js';

/** Populates req.user from the bearer token. */
export const requireAuth = asyncHandler(async (req, res, next) => {
  const header = req.get('authorization') ?? '';
  const [scheme, token] = header.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) throw unauthorized();

  const payload = verifyAccessToken(token);
  const user = await User.findById(payload.sub);
  if (!user || !user.isActive) throw unauthorized('Account is inactive');

  req.user = user;
  next();
});

export const requireRole =
  (...roles) =>
  (req, res, next) => {
    if (!req.user) return next(unauthorized());
    if (!roles.includes(req.user.role)) {
      return next(forbidden('This action requires a different role'));
    }
    next();
  };

export const requireClinician = requireRole(ROLES.DOCTOR, ROLES.STAFF);

/**
 * Resolves which patient a request is operating on and enforces access.
 *
 * Patients may only ever touch their own record. Clinicians may act on any
 * patient in the clinic. Every clinical route funnels through here rather than
 * comparing ids inline — one place to audit means one place to get right.
 *
 * Reads `:patientId` from the path, falling back to the caller's own id.
 */
export const resolvePatientScope = asyncHandler(async (req, res, next) => {
  const requested = req.params.patientId ?? req.query.patientId ?? null;

  if (req.user.role === ROLES.PATIENT) {
    if (requested && requested !== req.user._id.toString() && requested !== 'me') {
      throw forbidden('You can only access your own health record');
    }
    req.patientId = req.user._id;
    return next();
  }

  // Clinician path.
  if (!requested || requested === 'me') {
    throw forbidden('A patient must be specified for clinician access');
  }
  const patient = await User.findOne({ _id: requested, role: ROLES.PATIENT });
  if (!patient) throw forbidden('Unknown patient');

  req.patientId = patient._id;
  req.patientUser = patient;
  next();
});

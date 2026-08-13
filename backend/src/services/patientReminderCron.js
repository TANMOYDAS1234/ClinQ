import { inClinicTz } from '../utils/clinicTime.js';
import { User, ROLES } from '../models/User.js';
import { GlucoseReading } from '../models/GlucoseReading.js';
import { LabResult } from '../models/LabResult.js';
import { Prescription } from '../models/Prescription.js';
import { sendGlucoseCheckinPush, sendLabUploadNudgePush } from './notifications.js';
import { logger } from '../config/logger.js';

/**
 * Two gentle, patient-facing nudges the app owes but never sent: "log a blood
 * sugar" and "upload the lab report your doctor advised".
 *
 * Both are deliberately quiet. They fire only in the late morning — 9:00 for the
 * glucose check-in, 11:00 for the lab nudge — so a reminder never lands at night
 * (the fixed daytime hours ARE the quiet-hours guard; nothing here can fire
 * between dusk and morning). Each is capped so it can never become a daily
 * drumbeat: the glucose nudge backs off the longer a patient stays away, and the
 * lab nudge is sent at most three times per advised report.
 *
 * Dedup is a per-day date flag rather than a persisted log, matching the med
 * cron's philosophy: the worst a mid-morning restart can cost is one repeated
 * nudge, which is not worth a collection to prevent.
 */
const TICK_MS = 5 * 60 * 1000;
const GLUCOSE_HOUR = 9;
const LAB_HOUR = 11;

/** Days after the doctor advised a test that we nudge — then never again. */
const LAB_NUDGE_DAYS = new Set([3, 7, 12]);

let glucosePassDate = null;
let labPassDate = null;

/**
 * Whether a patient who last logged `gapDays` ago should be nudged this morning.
 *
 * Daily for the first three lapsed days (a diabetic should log daily, so an
 * early nudge is a service, not a nag), then every other day up to a fortnight,
 * then weekly — so someone who simply will not log settles at one nudge a week
 * instead of an uninstall-inducing daily one. `0` means they already logged
 * today; never nudge then.
 */
export function shouldNudgeGlucose(gapDays) {
  if (gapDays <= 0) return false;
  if (gapDays <= 3) return true;
  if (gapDays <= 14) return gapDays % 2 === 1;
  return gapDays % 7 === 0;
}

async function glucosePass(now) {
  const patients = await User.find({ role: ROLES.PATIENT, isActive: true })
    .select('_id deviceTokens language createdAt')
    .lean();

  let sent = 0;
  for (const patient of patients) {
    if (!patient.deviceTokens?.length) continue;

    // eslint-disable-next-line no-await-in-loop
    const last = await GlucoseReading.findOne({ patient: patient._id })
      .sort({ measuredAt: -1 })
      .select('measuredAt')
      .lean();

    // No reading ever → count from signup, so a patient who has logged nothing
    // since registering is still eventually (and gently) reminded.
    const sinceInstant = last?.measuredAt ?? patient.createdAt;
    if (!sinceInstant) continue;

    const gapDays = now.startOf('day').diff(inClinicTz(sinceInstant).startOf('day'), 'day');
    if (!shouldNudgeGlucose(gapDays)) continue;

    // eslint-disable-next-line no-await-in-loop
    await sendGlucoseCheckinPush({ patient, gapDays });
    sent += 1;
  }
  logger.info({ candidates: patients.length, sent }, 'glucose check-in nudges sent');
}

async function labPass(now) {
  const patients = await User.find({ role: ROLES.PATIENT, isActive: true })
    .select('_id deviceTokens language')
    .lean();

  let sent = 0;
  for (const patient of patients) {
    if (!patient.deviceTokens?.length) continue;

    // The most recent active prescription that actually advised a test.
    // eslint-disable-next-line no-await-in-loop
    const rx = await Prescription.findOne({
      patient: patient._id,
      isActive: true,
      'labTestsAdvised.0': { $exists: true },
    })
      .sort({ createdAt: -1 })
      .select('createdAt labTestsAdvised')
      .lean();
    if (!rx) continue;

    const gapDays = now.startOf('day').diff(inClinicTz(rx.createdAt).startOf('day'), 'day');
    if (!LAB_NUDGE_DAYS.has(gapDays)) continue;

    // Responded already? Any upload dated on/after the advice means they are on
    // it — matching by upload time rather than test name, which the doctor and
    // the report label rarely spell identically.
    // eslint-disable-next-line no-await-in-loop
    const upload = await LabResult.findOne({ patient: patient._id, createdAt: { $gte: rx.createdAt } })
      .select('_id')
      .lean();
    if (upload) continue;

    // eslint-disable-next-line no-await-in-loop
    await sendLabUploadNudgePush({ patient, tests: rx.labTestsAdvised });
    sent += 1;
  }
  logger.info({ candidates: patients.length, sent }, 'lab-upload nudges sent');
}

async function tick() {
  const now = inClinicTz(new Date());
  const today = now.format('YYYY-MM-DD');
  const hour = now.hour();

  if (hour === GLUCOSE_HOUR && glucosePassDate !== today) {
    glucosePassDate = today;
    await glucosePass(now);
  }
  if (hour === LAB_HOUR && labPassDate !== today) {
    labPassDate = today;
    await labPass(now);
  }
}

let handle = null;

/** Starts the cron. Idempotent; `unref` so it never holds the process open. */
export function startPatientReminderCron() {
  if (handle) return;
  handle = setInterval(() => {
    tick().catch((err) => logger.error({ err }, 'patient reminder tick failed'));
  }, TICK_MS);
  handle.unref?.();
  logger.info({ glucoseHour: GLUCOSE_HOUR, labHour: LAB_HOUR }, 'patient reminder cron started');
}

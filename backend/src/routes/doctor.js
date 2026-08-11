import { Router } from 'express';
import dayjs from 'dayjs';
import { z } from 'zod';
import { requireAuth, requireClinician } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound, conflict } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { User, ROLES } from '../models/User.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { ClinicalAlert, ALERT_SEVERITY } from '../models/ClinicalAlert.js';
import { Appointment } from '../models/Appointment.js';
import { GlucoseReading } from '../models/GlucoseReading.js';
import { ChatSession } from '../models/ChatSession.js';
import { ChatMessage } from '../models/ChatMessage.js';
import { MediaAsset } from '../models/MediaAsset.js';
import { KnowledgeChunk } from '../models/KnowledgeChunk.js';
import { Hba1cRecord } from '../models/Hba1cRecord.js';
import { FootAssessment } from '../models/FootAssessment.js';
import { LabResult } from '../models/LabResult.js';
import { buildAnalytes } from '../services/analyteCatalog.js';
import { FoodLog } from '../models/FoodLog.js';
import { Prescription } from '../models/Prescription.js';
import { toE164 } from '../utils/phone.js';
import { ClinicSettings, getClinicSettings } from '../models/ClinicSettings.js';
import { acknowledgeAlert, resolveAlert } from '../services/alerts.js';
import {
  computeAdherence,
  glucoseTrends,
  computeHealthScore,
  monitoringSignals,
  clinicAnalytics,
  isCheckInOverdue,
} from '../services/analytics.js';
import { buildPatientContext } from '../services/patientContext.js';
import { embed } from '../services/ai/gemini.js';
import { paged, pageParams } from '../utils/pagination.js';
import { logger } from '../config/logger.js';

const router = Router();
router.use(requireAuth, requireClinician);

// Clinic-wide analytics are recomputed at most this often. The dashboard polls
// every ~20s, but this aggregation over every reading changes slowly, so it is
// served from a short in-process cache rather than run on each hit — the one
// thing that would melt at 100k+ readings.
const ANALYTICS_TTL_MS = 120000;
let analyticsCache = { key: null, at: 0, data: null };

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

router.get(
  '/overview',
  asyncHandler(async (req, res) => {
    const dayStart = dayjs().startOf('day').toDate();
    const dayEnd = dayjs().endOf('day').toDate();

    const [
      patientCount,
      activeToday,
      alertCounts,
      appointmentsToday,
      completedToday,
      pendingReviews,
      unreadMessages,
      unreadNutrition,
      riskGroups,
    ] = await Promise.all([
      User.countDocuments({ role: ROLES.PATIENT, isActive: true }),
      GlucoseReading.distinct('patient', { measuredAt: { $gte: dayStart } }).then((ids) => ids.length),
      ClinicalAlert.aggregate([
        { $match: { status: 'open' } },
        { $group: { _id: '$severity', count: { $sum: 1 } } },
      ]),
      Appointment.countDocuments({
        scheduledFor: { $gte: dayStart, $lte: dayEnd },
        status: { $nin: ['cancelled'] },
      }),
      // Today's finished consultations — the "Completed" headline.
      Appointment.countDocuments({
        scheduledFor: { $gte: dayStart, $lte: dayEnd },
        status: 'completed',
      }),
      // Conversations flagged for the doctor to read — the "Pending" headline.
      ChatSession.countDocuments({ flaggedForReview: true, isArchived: false }),
      // Patient messages no one at the clinic has opened yet — "New messages".
      ChatMessage.countDocuments({ role: 'user', seenByClinicAt: null }),
      // How many of those are in a nutrition thread. The doctor's Patients tab
      // shows only the care conversation; nutrition lives behind Chat review's
      // Nutrition filter. Without the split, the headline counted messages the
      // doctor then could not find anywhere on the screen it was shown.
      unreadNutritionCount(),
      // Only profiles belonging to an ACTIVE patient. A deactivated or removed
      // patient can leave a lingering profile behind, and counting those inflated
      // the risk donut past the real headcount (the "9 vs 7" on the dashboard).
      PatientProfile.aggregate([
        { $lookup: { from: 'users', localField: 'user', foreignField: '_id', as: 'u' } },
        { $unwind: '$u' },
        { $match: { 'u.isActive': true, 'u.role': ROLES.PATIENT } },
        { $group: { _id: '$riskBand', count: { $sum: 1 } } },
      ]),
    ]);

    const bySeverity = Object.fromEntries(alertCounts.map((a) => [a._id, a.count]));
    const byRisk = Object.fromEntries(riskGroups.map((r) => [r._id ?? 'low', r.count]));

    const [dietPatients, foodLogsToday, newPatientsToday, reviews] = await Promise.all([
      PatientProfile.countDocuments({ assignedDietician: { $ne: null } }),
      FoodLog.countDocuments({ createdAt: { $gte: dayStart } }),
      User.countDocuments({ role: ROLES.PATIENT, createdAt: { $gte: dayStart } }),
      nutritionReviews(),
    ]);

    res.json({
      patientCount,
      newPatientsToday,
      activeToday,
      openAlerts: {
        emergency: bySeverity.emergency ?? 0,
        urgent: bySeverity.urgent ?? 0,
        warning: bySeverity.warning ?? 0,
        total: alertCounts.reduce((s, a) => s + a.count, 0),
      },
      appointmentsToday,
      completedToday,
      pendingReviews,
      unreadMessages,
      unreadNutrition,
      riskDistribution: {
        low: byRisk.low ?? 0,
        moderate: byRisk.moderate ?? 0,
        high: byRisk.high ?? 0,
        critical: byRisk.critical ?? 0,
      },
      nutrition: {
        dietPatients,
        foodLogsToday,
        reviews,
      },
    });
  }),
);

/**
 * Clinic-wide analytics for the dashboard's population charts: the daily
 * low/in-range/high control trend, check-in engagement, and the roster
 * monitoring counts. Served from a short in-process cache so the dashboard's
 * frequent polling never runs the full aggregation more than once per TTL.
 */
router.get(
  '/analytics',
  asyncHandler(async (req, res) => {
    const days = Math.min(180, Math.max(7, Number(req.query.days) || 30));
    const key = `d${days}`;
    const now = Date.now();
    if (analyticsCache.key === key && now - analyticsCache.at < ANALYTICS_TTL_MS && analyticsCache.data) {
      return res.json({ ...analyticsCache.data, cached: true });
    }
    const data = await clinicAnalytics({ days });
    analyticsCache = { key, at: now, data };
    res.json({ ...data, cached: false });
  }),
);

/**
 * Unread patient messages sitting in a nutrition thread.
 *
 * Split out because the two live in different places in the doctor's app: the
 * care conversation is on the Patients tab, the nutrition one only behind Chat
 * review's Nutrition filter. A single "12 unread" sent the doctor to a screen
 * where some of those twelve were not, with nothing to say where they were.
 */
async function unreadNutritionCount() {
  const sessions = await ChatSession.find({ kind: 'nutrition' }).select('_id').lean();
  if (sessions.length === 0) return 0;
  return ChatMessage.countDocuments({
    role: 'user',
    seenByClinicAt: null,
    session: { $in: sessions.map((s) => s._id) },
  });
}

/**
 * The nutrition cards on the doctor's home: patients on a review cadence, worst
 * first, with where they are in the cycle and what their logging actually looks
 * like.
 *
 * The flag is derived from real food-log activity rather than from nutrient
 * analysis — the app records meals, not sodium, and a card that claimed
 * otherwise would be inventing a number the doctor might act on.
 */
async function nutritionReviews(limit = 4) {
  // Every patient, on the clinic-wide cadence.
  //
  // This used to require `assignedDietician` and a per-patient
  // `dietReviewIntervalDays`. Both moved: one dietician covers everyone, and
  // the cadence became a clinic setting. Nothing sets those two fields any
  // more, so the query matched no one and the whole Nutrition Reviews section
  // silently disappeared from the doctor's home.
  const { dietReviewIntervalDays: intervalDays } = await getClinicSettings();

  const profiles = await PatientProfile.find({})
    .populate('user', 'name isActive')
    .lean();

  const weekAgo = dayjs().subtract(7, 'day').toDate();
  const cards = await Promise.all(
    profiles
      .filter((p) => p.user && p.user.isActive !== false)
      .map(async (p) => {
        const since = p.lastDietReviewAt ?? p.createdAt;
        const day = Math.min(dayjs().diff(dayjs(since), 'day'), intervalDays);
        const [mealsThisWeek, lastLog] = await Promise.all([
          FoodLog.countDocuments({ patient: p.user._id, createdAt: { $gte: weekAgo } }),
          FoodLog.findOne({ patient: p.user._id }).sort({ createdAt: -1 }).select('createdAt').lean(),
        ]);
        return {
          patientId: String(p.user._id),
          name: p.user.name,
          day,
          intervalDays,
          mealsThisWeek,
          lastLogAt: lastLog?.createdAt ?? null,
        };
      }),
  );

  // Closest to (or past) their review date first: those are the ones the doctor
  // can still do something about today.
  cards.sort((a, b) => b.day / b.intervalDays - a.day / a.intervalDays);
  return cards.slice(0, limit);
}

/**
 * The doctor's Patients tab: three counts, the queue of what is outstanding, and
 * the newest meals logged across the clinic.
 *
 * One endpoint rather than three so the counts and the queue below them are
 * always describing the same moment.
 */
router.get(
  '/worklist',
  asyncHandler(async (req, res) => {
    const [patients, flaggedSessions, prescribedIds, recentMeals] = await Promise.all([
      User.find({ role: ROLES.PATIENT, isActive: true }).select('name createdAt').lean(),
      ChatSession.find({ flaggedForReview: true, isArchived: false })
        .sort({ lastMessageAt: -1 })
        .limit(20)
        .populate('patient', 'name')
        .lean(),
      Prescription.distinct('patient'),
      FoodLog.find({})
        .sort({ createdAt: -1 })
        .limit(8)
        .populate('patient', 'name')
        .lean(),
    ]);

    const hasPlan = new Set(prescribedIds.map(String));
    // A patient with no prescription is the doctor's outstanding work; the
    // longest-waiting first, because that is the one going cold.
    const needsPlan = patients
      .filter((p) => !hasPlan.has(String(p._id)))
      .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));

    const queue = [
      ...flaggedSessions
        .filter((s) => s.patient)
        .map((s) => ({
          kind: 'review',
          patientId: String(s.patient._id),
          name: s.patient.name,
          days: dayjs().diff(dayjs(s.lastMessageAt ?? s.createdAt), 'day'),
        })),
      ...needsPlan.map((p) => ({
        kind: 'plan',
        patientId: String(p._id),
        name: p.name,
        days: dayjs().diff(dayjs(p.createdAt), 'day'),
      })),
    ];

    res.json({
      counts: {
        patients: patients.length,
        reviews: flaggedSessions.length,
        plans: needsPlan.length,
      },
      // Capped so the tab stays a worklist and not an archive; `counts` above
      // still reports the true totals, so a trimmed list never reads as "done".
      queue: queue.slice(0, 12),
      recentMeals: recentMeals
        .filter((f) => f.patient)
        .map((f) => ({
          id: String(f._id),
          patientId: String(f.patient._id),
          patientName: f.patient.name,
          mealType: f.mealType,
          photoUrl: f.photo ? `/api/v1/uploads/${f.photo}/raw` : null,
          createdAt: f.createdAt,
        })),
    });
  }),
);

/**
 * Register a walk-in patient from the clinic side.
 *
 * Mirrors the dietician-creation route: some patients are enrolled at the desk
 * on a clinic phone rather than downloading the app first, and without this the
 * doctor has no way to start a record for them.
 */
router.post(
  '/patients',
  validate({
    body: z.object({
      name: z.string().trim().min(2).max(120),
      // Normalised to E.164 first: a number stored as bare digits is an
      // account whose owner can never sign in, because login sends +91.
      phone: z
        .string()
        .trim()
        .transform(toE164)
        .pipe(z.string().regex(/^\+?[1-9]\d{7,14}$/, 'Enter a valid phone number')),
      password: z.string().min(8, 'At least 8 characters').max(128),
    }),
  }),
  audit('create', 'User'),
  asyncHandler(async (req, res) => {
    const { name, phone, password } = req.body;
    if (await User.exists({ phone })) throw conflict('An account with this phone number already exists');

    const user = new User({
      name,
      phone,
      role: ROLES.PATIENT,
      consent: {
        termsAcceptedAt: new Date(),
        dataProcessingAcceptedAt: new Date(),
        aiDisclaimerAcceptedAt: new Date(),
      },
    });
    await user.setPassword(password);
    await user.save();
    await PatientProfile.create({ user: user._id });

    res.status(201).json({ id: String(user._id), name: user.name, phone: user.phone });
  }),
);

// ---------------------------------------------------------------------------
// Patient list + segmentation
// ---------------------------------------------------------------------------

router.get(
  '/patients',
  validate({
    query: pageParams.and(
      z.object({
        riskBand: z.enum(['low', 'moderate', 'high', 'critical']).optional(),
        search: z.string().max(120).optional(),
        sort: z.enum(['risk', 'name', 'recent']).default('risk'),
      }),
    ),
  }),
  audit('read', 'PatientList'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip, riskBand, search, sort } = q(req);

    const userFilter = { role: ROLES.PATIENT, isActive: true };
    if (search) {
      // Escaped so a patient searching for "a.b" cannot inject a regex.
      const safe = search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      userFilter.$or = [{ name: new RegExp(safe, 'i') }, { phone: new RegExp(safe, 'i') }];
    }

    let profileFilter = {};
    if (riskBand) profileFilter = { riskBand };

    const matchingProfiles = await PatientProfile.find(profileFilter)
      .select('user riskScore riskBand checkInIntervalDays')
      .lean();
    const profileMap = new Map(matchingProfiles.map((p) => [p.user.toString(), p]));

    if (riskBand) userFilter._id = { $in: matchingProfiles.map((p) => p.user) };

    const sortSpec = sort === 'name' ? { name: 1 } : { createdAt: -1 };
    const [users, total] = await Promise.all([
      // avatarAssetId included so a photo the patient sets is visible to the
      // clinic. Without it the field never left the database and the doctor's
      // list showed an initial for a patient who had uploaded a picture.
      User.find(userFilter)
        .sort(sortSpec)
        .skip(skip)
        .limit(limit)
        .select('name phone createdAt avatarAssetId')
        .lean(),
      User.countDocuments(userFilter),
    ]);

    const ids = users.map((u) => u._id);
    const [lastReadings, alertCounts, lastMessages, unreadCounts, signals] = await Promise.all([
      GlucoseReading.aggregate([
        { $match: { patient: { $in: ids } } },
        { $sort: { measuredAt: -1 } },
        { $group: { _id: '$patient', measuredAt: { $first: '$measuredAt' }, value: { $first: '$valueMgDl' } } },
      ]),
      ClinicalAlert.aggregate([
        { $match: { patient: { $in: ids }, status: 'open' } },
        { $group: { _id: '$patient', count: { $sum: 1 } } },
      ]),
      // Newest turn per patient, whoever wrote it, so the row reads like an
      // inbox: what was last said and when, not merely that a thread exists.
      ChatMessage.aggregate([
        { $match: { patient: { $in: ids } } },
        { $sort: { createdAt: -1 } },
        {
          $group: {
            _id: '$patient',
            content: { $first: '$content' },
            role: { $first: '$role' },
            createdAt: { $first: '$createdAt' },
            urgency: { $first: '$triage.urgency' },
            attachments: { $first: '$attachments' },
          },
        },
      ]),
      // Unread means the patient wrote it and no clinician has opened the
      // thread since. `seenByClinicAt` is stamped when the thread is read, so
      // the badge and the patient's "Seen by the clinic" mark cannot disagree.
      ChatMessage.aggregate([
        { $match: { patient: { $in: ids }, role: 'user', seenByClinicAt: null } },
        { $group: { _id: '$patient', count: { $sum: 1 } } },
      ]),
      // Sparkline + trend + recency for each row's monitoring strip.
      monitoringSignals(ids),
    ]);

    const readingMap = new Map(lastReadings.map((r) => [r._id.toString(), r]));
    const alertMap = new Map(alertCounts.map((a) => [a._id.toString(), a.count]));
    const messageMap = new Map(lastMessages.map((m) => [m._id.toString(), m]));
    const unreadMap = new Map(unreadCounts.map((u) => [u._id.toString(), u.count]));

    // The kind/mime of every newest-message attachment, so a media-only turn
    // previews as its TYPE — with plain text plus a `mediaType` the app renders
    // as a subtle icon (no emoji) — instead of a blank line or a transcript.
    const lastAttachmentIds = lastMessages.flatMap((m) => m.attachments ?? []);
    const assetMap = new Map(
      (await MediaAsset.find({ _id: { $in: lastAttachmentIds } })
        .select('_id kind mimeType')
        .lean()).map((a) => [a._id.toString(), a]),
    );
    // Returns { preview, mediaType } where mediaType is voice|photo|pdf|document|
    // file|null. A voice note always reads as a voice message; a caption
    // otherwise wins; media with no caption falls back to a plain type label.
    const mediaInfo = (m) => {
      const atts = (m?.attachments ?? []).map((a) => assetMap.get(a.toString())).filter(Boolean);
      if (atts.some((a) => a.kind === 'voice_note' || (a.mimeType || '').startsWith('audio/'))) {
        return { preview: 'Voice message', mediaType: 'voice' };
      }
      const doc = atts.find(
        (a) => (a.mimeType || '').startsWith('application/') || (a.mimeType || '').startsWith('text/'),
      );
      let mediaType = null;
      if (doc) mediaType = doc.mimeType === 'application/pdf' ? 'pdf' : 'document';
      else if (atts.some((a) => (a.mimeType || '').startsWith('image/'))) mediaType = 'photo';
      else if (atts.length) mediaType = 'file';

      const text = (m?.content || '').trim();
      if (text) return { preview: text.slice(0, 140), mediaType };
      switch (mediaType) {
        case 'pdf':
          return { preview: 'PDF document', mediaType };
        case 'document':
          return { preview: 'Document', mediaType };
        case 'photo':
          return { preview: 'Photo', mediaType };
        case 'file':
          return { preview: 'Attachment', mediaType };
        default:
          return { preview: '', mediaType: null };
      }
    };

    const items = users.map((u) => {
      const id = u._id.toString();
      const profile = profileMap.get(id);
      const reading = readingMap.get(id);
      const lastMsg = messageMap.get(id);
      const media = lastMsg ? mediaInfo(lastMsg) : null;
      return {
        id: u._id,
        name: u.name,
        phone: u.phone,
        // `lean()` skips the schema's toJSON, so build the URL by hand.
        avatarUrl: u.avatarAssetId ? `/api/v1/uploads/${u.avatarAssetId}/raw` : null,
        // Inbox fields. Null where a patient has never written — the row then
        // reads as a patient the clinic can start a conversation with, rather
        // than an empty message.
        lastMessage: lastMsg
          ? {
              // Trimmed server-side: a 4000-character message has no business
              // crossing the wire to fill a two-line preview. `mediaType` lets
              // the app draw a subtle icon for a media-only turn.
              preview: media.preview,
              mediaType: media.mediaType,
              role: lastMsg.role,
              at: lastMsg.createdAt,
              urgency: lastMsg.urgency ?? 'routine',
            }
          : null,
        unreadCount: unreadMap.get(id) ?? 0,
        riskScore: profile?.riskScore ?? 0,
        riskBand: profile?.riskBand ?? 'low',
        lastReadingAt: reading?.measuredAt ?? null,
        lastReadingValue: reading?.value ?? null,
        openAlertCount: alertMap.get(id) ?? 0,
        // Continuous-monitoring signals for the row's sparkline + trend badge.
        spark: signals.get(id)?.spark ?? [],
        trend: signals.get(id)?.direction ?? 'flat',
        trendDelta: signals.get(id)?.trendDelta ?? null,
        checkInIntervalDays: profile?.checkInIntervalDays ?? null,
        checkInOverdue: isCheckInOverdue(reading?.measuredAt ?? null, profile?.checkInIntervalDays),
      };
    });

    if (sort === 'risk') items.sort((a, b) => b.riskScore - a.riskScore);
    if (sort === 'recent') {
      items.sort((a, b) => new Date(b.lastReadingAt ?? 0) - new Date(a.lastReadingAt ?? 0));
    }

    res.json(paged(items, { page, limit, total }));
  }),
);

router.get(
  '/patients/:id/summary',
  audit('read', 'PatientSummary'),
  asyncHandler(async (req, res) => {
    const patient = await User.findOne({ _id: req.params.id, role: ROLES.PATIENT }).lean();
    if (!patient) throw notFound('Patient not found');
    req.patientId = patient._id;

    const [profile, healthScore, trends, adherence, alerts, latestHba1c, footAssessments, context, labResults, rxForTests] =
      await Promise.all([
        PatientProfile.findOne({ user: patient._id }).populate('assignedDietician', 'name phone').lean(),
        computeHealthScore(patient._id, { days: 30 }),
        glucoseTrends(patient._id, { days: 90 }),
        computeAdherence(patient._id, { days: 30 }),
        ClinicalAlert.find({ patient: patient._id }).sort({ createdAt: -1 }).limit(20).lean(),
        Hba1cRecord.find({ patient: patient._id }).sort({ testedOn: -1 }).limit(6).lean(),
        FootAssessment.find({ patient: patient._id }).sort({ assessedAt: -1 }).limit(5).lean(),
        buildPatientContext(patient._id),
        LabResult.find({ patient: patient._id })
          .sort({ createdAt: -1 })
          .limit(20)
          .populate('photo', 'mimeType originalName sizeBytes')
          .lean(),
        // What the doctor has already asked this patient to get done. Without
        // it the prescribing screen offered a fresh list of tests with no way
        // to see that HbA1c was ordered a fortnight ago and is still pending.
        Prescription.find({ patient: patient._id, isActive: true })
          .select('labTestsAdvised')
          .lean(),
      ]);

    res.json({
      patient: {
        id: patient._id,
        name: patient.name,
        phone: patient.phone,
        avatarUrl: patient.avatarAssetId ? `/api/v1/uploads/${patient.avatarAssetId}/raw` : null,
        email: patient.email ?? null,
        language: patient.language,
        dateOfBirth: patient.dateOfBirth ?? null,
        gender: patient.gender,
        age: patient.dateOfBirth ? dayjs().diff(dayjs(patient.dateOfBirth), 'year') : null,
      },
      profile,
      healthScore,
      trends,
      adherence,
      hba1cHistory: latestHba1c.map((h) => ({ percentage: h.percentage, testedOn: h.testedOn })),
      footAssessments: footAssessments.map((f) => ({
        id: f._id,
        assessedAt: f.assessedAt,
        site: f.site,
        finalRiskLevel: f.finalRiskLevel,
      })),
      labResults: labResults.map((r) => {
        const asset = r.photo && typeof r.photo === 'object' ? r.photo : null;
        const photoId = asset ? asset._id : r.photo;
        return {
          id: String(r._id),
          testName: r.testName,
          note: r.note ?? '',
          photoUrl: photoId ? `/api/v1/uploads/${photoId}/raw` : null,
          // So the doctor's screen can tell a scan from a PDF, as the
          // patient's now does.
          mimeType: asset?.mimeType ?? null,
          originalName: asset?.originalName ?? null,
          // What was transcribed off the page, so the doctor sees the numbers
          // without opening the file — and sees plainly when a report could
          // not be read and still needs their eyes.
          analysisStatus: r.analysis?.status ?? null,
          analysisSummary: r.analysis?.summary ?? null,
          hba1cPercent: r.analysis?.hba1cPercent ?? null,
          abnormal: r.analysis?.abnormal ?? [],
          // Uniform value/range/flag list for the record's structured display.
          analytes: buildAnalytes(r.analysis),
          testedOn: r.analysis?.testedOn ?? null,
          createdAt: r.createdAt,
        };
      }),
      labTestsAdvised: [
        ...new Set((rxForTests ?? []).flatMap((p) => p.labTestsAdvised ?? []).filter(Boolean)),
      ],
      alerts: alerts.map(serialiseAlert),
      // The same summary the AI assistant sees — useful for the doctor to
      // understand why it answered the way it did.
      aiContext: context.text,
    });
  }),
);

// ---------------------------------------------------------------------------
// Alerts
// ---------------------------------------------------------------------------

router.get(
  '/alerts',
  validate({
    query: pageParams.and(
      z.object({
        status: z.enum(['open', 'acknowledged', 'resolved', 'dismissed']).optional(),
        severity: z.enum(ALERT_SEVERITY).optional(),
      }),
    ),
  }),
  audit('read', 'ClinicalAlert'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip, status, severity } = q(req);
    const filter = { ...(status ? { status } : {}), ...(severity ? { severity } : {}) };

    const [items, total] = await Promise.all([
      ClinicalAlert.find(filter)
        .sort({ severity: -1, createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .populate('patient', 'name phone')
        .lean(),
      ClinicalAlert.countDocuments(filter),
    ]);

    res.json(paged(items.map(serialiseAlert), { page, limit, total }));
  }),
);

router.post(
  '/alerts/:id/acknowledge',
  audit('update', 'ClinicalAlert'),
  asyncHandler(async (req, res) => {
    const alert = await acknowledgeAlert(req.params.id, req.user._id);
    if (!alert) throw notFound('Alert not found');
    res.json({ alert: serialiseAlert(alert) });
  }),
);

router.post(
  '/alerts/:id/resolve',
  validate({ body: z.object({ notes: z.string().max(2000).optional() }) }),
  audit('update', 'ClinicalAlert'),
  asyncHandler(async (req, res) => {
    const alert = await resolveAlert(req.params.id, req.user._id, req.body.notes);
    if (!alert) throw notFound('Alert not found');
    res.json({ alert: serialiseAlert(alert) });
  }),
);

// ---------------------------------------------------------------------------
// AI chat monitoring
// ---------------------------------------------------------------------------

router.get(
  '/chat-review',
  validate({
    query: pageParams.and(
      z.object({
        urgency: z.enum(['routine', 'advice', 'urgent', 'emergency']).optional(),
        kind: z.enum(['care', 'nutrition']).optional(),
      }),
    ),
  }),
  audit('read', 'ChatSession'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip, urgency, kind } = q(req);
    // `flagged` is read from the raw query rather than the zod schema: pageParams
    // is `.passthrough()`, so an intersected `z.coerce.boolean()` would keep the
    // string on one side and a boolean on the other and fail to merge. Defaults
    // to true (only flagged threads), false only when explicitly "false".
    const flagged = req.query.flagged !== 'false';
    const filter = {
      ...(flagged ? { flaggedForReview: true } : {}),
      ...(urgency ? { highestUrgency: urgency } : {}),
      // `nutrition` is an equality match; `care` has to be `$ne: 'nutrition'`
      // because sessions created before `kind` existed carry no value at all —
      // a Mongoose default never backfills. See ChatSession.kind.
      ...(kind === 'nutrition'
        ? { kind: 'nutrition' }
        : kind === 'care'
          ? { kind: { $ne: 'nutrition' } }
          : {}),
    };

    const [items, total] = await Promise.all([
      ChatSession.find(filter)
        .sort({ lastMessageAt: -1 })
        .skip(skip)
        .limit(limit)
        .populate('patient', 'name phone')
        .lean(),
      ChatSession.countDocuments(filter),
    ]);

    // Unread patient messages per conversation, so the doctor can see which
    // rows are new rather than opening each in turn to find out. Counted only
    // for the page being returned, not the whole collection.
    const unreadBySession = new Map(
      (
        await ChatMessage.aggregate([
          {
            $match: {
              session: { $in: items.map((s) => s._id) },
              role: 'user',
              seenByClinicAt: null,
            },
          },
          { $group: { _id: '$session', count: { $sum: 1 } } },
        ])
      ).map((u) => [u._id.toString(), u.count]),
    );

    res.json(
      paged(
        items.map((s) => ({
          id: s._id,
          patientId: s.patient?._id,
          patientName: s.patient?.name ?? null,
          title: s.title,
          // `care` (assistant + doctor) or `nutrition` (the dietician's own
          // thread). Both are reviewable; the doctor needs to know which one
          // they are reading before they judge what was said in it.
          kind: s.kind ?? 'care',
          language: s.language,
          messageCount: s.messageCount,
          highestUrgency: s.highestUrgency,
          flaggedForReview: s.flaggedForReview,
          reviewedAt: s.reviewedAt ?? null,
          unreadCount: unreadBySession.get(s._id.toString()) ?? 0,
          lastMessageAt: s.lastMessageAt,
        })),
        { page, limit, total },
      ),
    );
  }),
);

router.get(
  '/chat-review/:sessionId',
  audit('read', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const session = await ChatSession.findById(req.params.sessionId).populate('patient', 'name phone').lean();
    if (!session) throw notFound('Conversation not found');
    req.patientId = session.patient?._id;

    // Attachments are populated because a food photo *is* the message: without
    // them the doctor sees an empty bubble above the assistant's reply and has
    // no way to judge whether that reply was right about the meal.
    const messages = await ChatMessage.find({ session: session._id })
      .sort({ seq: 1 })
      .populate('sender', 'name role')
      .populate('attachments', 'kind mimeType transcript originalName sizeBytes')
      .lean();

    res.json({
      session: {
        id: session._id,
        patientId: session.patient?._id,
        patientName: session.patient?.name ?? null,
        title: session.title,
        highestUrgency: session.highestUrgency,
        language: session.language,
      },
      messages: messages.map((m) => ({
        id: m._id,
        seq: m.seq,
        role: m.role,
        content: m.content,
        urgency: m.triage?.urgency ?? 'routine',
        matchedRules: m.triage?.matchedRules ?? [],
        ruleDriven: m.triage?.ruleDriven ?? false,
        // Which approved chunks grounded the answer — the audit trail for
        // "why did the assistant say that?".
        citations: (m.citations ?? []).map((c) => ({ id: c.chunk, title: c.title, score: c.score })),
        isFallback: m.isFallback ?? false,
        flaggedByPatient: m.flaggedByPatient ?? false,
        modelVersion: m.modelVersion ?? null,
        latencyMs: m.latencyMs ?? null,
        senderName: m.sender && typeof m.sender === 'object' ? (m.sender.name ?? null) : null,
        senderRole: m.sender && typeof m.sender === 'object' ? (m.sender.role ?? null) : null,
        attachments: (m.attachments ?? []).map((a) => {
          const id = (a?._id ?? a).toString?.() ?? a;
          return {
            id,
            url: `/api/v1/uploads/${id}/raw`,
            kind: a?.kind ?? null,
            mimeType: a?.mimeType ?? null,
            originalName: a?.originalName ?? null,
            sizeBytes: a?.sizeBytes ?? null,
            // A voice note's transcript is what triage actually read, so the
            // doctor should see the same text the rules did.
            transcript: a?.transcript ?? null,
          };
        }),
        createdAt: m.createdAt,
      })),
    });
  }),
);

router.post(
  '/chat-review/:sessionId/reviewed',
  asyncHandler(async (req, res) => {
    const session = await ChatSession.findByIdAndUpdate(
      req.params.sessionId,
      { flaggedForReview: false, reviewedBy: req.user._id, reviewedAt: new Date() },
      { new: true },
    );
    if (!session) throw notFound('Conversation not found');
    res.status(204).end();
  }),
);

// ---------------------------------------------------------------------------
// Knowledge base curation
// ---------------------------------------------------------------------------

const knowledgeSchema = z.object({
  docId: z.string().max(120),
  title: z.string().min(1).max(300),
  section: z.string().max(300).optional(),
  content: z.string().min(20).max(8000),
  language: z.enum(['en', 'bn', 'hi']).default('en'),
  category: z.enum([
    'diabetes_basics', 'hypoglycaemia', 'hyperglycaemia', 'insulin', 'oral_medication',
    'diet', 'exercise', 'foot_care', 'eye_care', 'kidney', 'hypertension',
    'sick_day_rules', 'emergency', 'clinic_info', 'general',
  ]),
  tags: z.array(z.string().max(40)).max(20).default([]),
  sourceCitation: z.string().max(500).optional(),
});

router.get(
  '/knowledge',
  validate({
    query: pageParams.and(
      z.object({
        status: z.enum(['draft', 'pending_review', 'approved', 'retired']).optional(),
        category: z.string().optional(),
        language: z.enum(['en', 'bn', 'hi']).optional(),
      }),
    ),
  }),
  asyncHandler(async (req, res) => {
    const { page, limit, skip, status, category, language } = q(req);
    const filter = {
      ...(status ? { status } : {}),
      ...(category ? { category } : {}),
      ...(language ? { language } : {}),
    };
    const [items, total] = await Promise.all([
      KnowledgeChunk.find(filter).sort({ updatedAt: -1 }).skip(skip).limit(limit).lean(),
      KnowledgeChunk.countDocuments(filter),
    ]);
    res.json(paged(items.map(serialiseChunk), { page, limit, total }));
  }),
);

router.post(
  '/knowledge',
  validate({ body: knowledgeSchema }),
  asyncHandler(async (req, res) => {
    const chunk = await KnowledgeChunk.create({ ...req.body, status: 'pending_review' });
    // Embed in the background — the doctor should not wait on the API, and the
    // chunk is not retrievable until approved anyway.
    embedChunk(chunk._id, req.body.content, req.body.title).catch((err) =>
      logger.error({ err: err?.message }, 'knowledge embedding failed'),
    );
    res.status(201).json({ chunk: serialiseChunk(chunk) });
  }),
);

router.patch(
  '/knowledge/:id',
  validate({ body: knowledgeSchema.partial() }),
  asyncHandler(async (req, res) => {
    const chunk = await KnowledgeChunk.findById(req.params.id);
    if (!chunk) throw notFound('Knowledge entry not found');

    const contentChanged = req.body.content && req.body.content !== chunk.content;
    Object.assign(chunk, req.body);
    if (contentChanged) {
      // Edited content must be re-approved — otherwise a chunk approved as safe
      // could be silently rewritten and still serve patients.
      chunk.status = 'pending_review';
      chunk.version += 1;
      chunk.approvedBy = undefined;
      chunk.approvedAt = undefined;
    }
    await chunk.save();

    if (contentChanged) {
      embedChunk(chunk._id, chunk.content, chunk.title).catch(() => {});
    }
    res.json({ chunk: serialiseChunk(chunk) });
  }),
);

router.post(
  '/knowledge/:id/approve',
  requireClinician,
  asyncHandler(async (req, res) => {
    const chunk = await KnowledgeChunk.findById(req.params.id).select('+embedding');
    if (!chunk) throw notFound('Knowledge entry not found');

    // Refuse to approve something that cannot actually be retrieved.
    if (!chunk.embedding?.length) {
      await embedChunk(chunk._id, chunk.content, chunk.title);
    }

    chunk.status = 'approved';
    chunk.approvedBy = req.user._id;
    chunk.approvedAt = new Date();
    await chunk.save();

    res.json({ chunk: serialiseChunk(chunk) });
  }),
);

router.post(
  '/knowledge/:id/retire',
  asyncHandler(async (req, res) => {
    const chunk = await KnowledgeChunk.findByIdAndUpdate(req.params.id, { status: 'retired' }, { new: true });
    if (!chunk) throw notFound('Knowledge entry not found');
    res.json({ chunk: serialiseChunk(chunk) });
  }),
);

async function embedChunk(id, content, title) {
  const vector = await embed(content, { taskType: 'RETRIEVAL_DOCUMENT', title });
  await KnowledgeChunk.updateOne(
    { _id: id },
    { embedding: vector, embeddingModel: process.env.GEMINI_EMBED_MODEL, embeddedAt: new Date() },
  );
}

// ---------------------------------------------------------------------------

function serialiseAlert(a) {
  const patient = a.patient && typeof a.patient === 'object' && a.patient.name ? a.patient : null;
  return {
    id: a._id,
    patientId: patient?._id ?? a.patient,
    patientName: patient?.name ?? null,
    patientPhone: patient?.phone ?? null,
    severity: a.severity,
    type: a.type,
    title: a.title,
    detail: a.detail ?? null,
    status: a.status,
    matchedRules: a.matchedRules ?? [],
    source: a.source,
    acknowledgedAt: a.acknowledgedAt ?? null,
    resolvedAt: a.resolvedAt ?? null,
    resolutionNotes: a.resolutionNotes ?? null,
    createdAt: a.createdAt,
  };
}

const serialiseChunk = (c) => ({
  id: c._id,
  docId: c.docId,
  title: c.title,
  section: c.section ?? null,
  content: c.content,
  language: c.language,
  category: c.category,
  tags: c.tags ?? [],
  status: c.status,
  version: c.version,
  hasEmbedding: Boolean(c.embeddedAt),
  sourceCitation: c.sourceCitation ?? null,
  approvedAt: c.approvedAt ?? null,
  updatedAt: c.updatedAt,
});

// ---------------------------------------------------------------------------
// Dietician assignment
// ---------------------------------------------------------------------------

/** Dieticians the doctor can assign a patient to. */
router.get(
  '/dieticians',
  asyncHandler(async (req, res) => {
    const items = await User.find({ role: ROLES.DIETICIAN, isActive: true })
      .select('name phone avatarAssetId')
      .sort({ name: 1 })
      .lean();
    res.json({
      items: items.map((d) => ({
        id: String(d._id),
        name: d.name,
        phone: d.phone,
        avatarAssetId: d.avatarAssetId ? String(d.avatarAssetId) : null,
        // Every other avatar in the app is consumed as a ready URL. Sending
        // only the asset id here meant the doctor's list could never draw the
        // dietician's own photo, however recently they had changed it.
        avatarUrl: d.avatarAssetId ? `/api/v1/uploads/${d.avatarAssetId}/raw` : null,
      })),
    });
  }),
);

/**
 * Clinic-wide settings. Read by the doctor's Dieticians screen.
 *
 * The review cadence lives here rather than on each patient for the same reason
 * dietician assignment does not: one or two dieticians and hundreds of
 * patients. Set once, it covers everyone.
 */
router.get(
  '/settings',
  asyncHandler(async (req, res) => {
    const settings = await getClinicSettings();
    res.json({ dietReviewIntervalDays: settings.dietReviewIntervalDays });
  }),
);

router.patch(
  '/settings',
  validate({
    body: z.object({
      dietReviewIntervalDays: z.coerce.number().int().min(1).max(90).optional(),
    }),
  }),
  audit('update', 'ClinicSettings'),
  asyncHandler(async (req, res) => {
    const update = {};
    if (req.body.dietReviewIntervalDays != null) {
      update.dietReviewIntervalDays = req.body.dietReviewIntervalDays;
    }

    const settings = await ClinicSettings.findOneAndUpdate(
      { key: 'clinic' },
      { $set: update, $setOnInsert: { key: 'clinic' } },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ).lean();

    res.json({ dietReviewIntervalDays: settings.dietReviewIntervalDays });
  }),
);

/** Create a dietician account the doctor can then assign to patients. */
router.post(
  '/dieticians',
  validate({
    body: z.object({
      name: z.string().trim().min(2).max(120),
      // Normalised to E.164 first: a number stored as bare digits is an
      // account whose owner can never sign in, because login sends +91.
      phone: z
        .string()
        .trim()
        .transform(toE164)
        .pipe(z.string().regex(/^\+?[1-9]\d{7,14}$/, 'Enter a valid phone number')),
      password: z.string().min(8, 'At least 8 characters').max(128),
    }),
  }),
  audit('create', 'User'),
  asyncHandler(async (req, res) => {
    const { name, phone, password } = req.body;
    if (await User.exists({ phone })) throw conflict('An account with this phone number already exists');
    const user = new User({
      name,
      phone,
      role: ROLES.DIETICIAN,
      consent: {
        termsAcceptedAt: new Date(),
        dataProcessingAcceptedAt: new Date(),
        aiDisclaimerAcceptedAt: new Date(),
      },
    });
    await user.setPassword(password);
    await user.save();
    res.status(201).json({ id: String(user._id), name: user.name, phone: user.phone });
  }),
);

/**
 * Assign (or clear) a patient's dietician and how often the food log should be
 * reviewed. `dieticianId: null` unassigns; `reviewIntervalDays: null` clears the
 * cadence.
 */
router.patch(
  '/patients/:id/dietician',
  validate({
    body: z.object({
      dieticianId: z.string().nullable().optional(),
      reviewIntervalDays: z.number().int().min(1).max(30).nullable().optional(),
    }),
  }),
  audit('update', 'PatientProfile'),
  asyncHandler(async (req, res) => {
    const { dieticianId, reviewIntervalDays } = req.body;
    const update = {};

    if (dieticianId !== undefined) {
      if (dieticianId) {
        const d = await User.findOne({ _id: dieticianId, role: ROLES.DIETICIAN, isActive: true }).select('_id').lean();
        if (!d) throw notFound('Dietician not found');
        update.assignedDietician = d._id;
      } else {
        update.assignedDietician = null;
      }
    }
    if (reviewIntervalDays !== undefined) update.dietReviewIntervalDays = reviewIntervalDays;

    const profile = await PatientProfile.findOneAndUpdate({ user: req.params.id }, { $set: update }, { new: true })
      .populate('assignedDietician', 'name phone')
      .lean();
    if (!profile) throw notFound('Patient not found');

    res.json({
      assignedDietician: profile.assignedDietician
        ? { id: String(profile.assignedDietician._id), name: profile.assignedDietician.name, phone: profile.assignedDietician.phone }
        : null,
      reviewIntervalDays: profile.dietReviewIntervalDays ?? null,
    });
  }),
);

export default router;

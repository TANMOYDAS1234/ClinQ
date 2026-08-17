import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, requireDietician } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler, notFound } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { User } from '../models/User.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { Medication } from '../models/Medication.js';
import { Prescription } from '../models/Prescription.js';
import { LabResult } from '../models/LabResult.js';
import { Hba1cRecord } from '../models/Hba1cRecord.js';
import { VitalRecord } from '../models/VitalRecord.js';
import { GlucoseReading } from '../models/GlucoseReading.js';
import { FoodLog } from '../models/FoodLog.js';
import { buildAnalytes } from '../services/analyteCatalog.js';
import { ChatSession } from '../models/ChatSession.js';
import { ChatMessage } from '../models/ChatMessage.js';
import { DietPlan } from '../models/DietPlan.js';
import { notifyPatientOfClinicianReply } from '../services/notifications.js';
import { dayjs } from '../utils/clinicTime.js';
import { getClinicSettings } from '../models/ClinicSettings.js';

/**
 * The dietician panel API. A dietician only ever sees the patients a doctor has
 * assigned to them, and only the nutrition-relevant slice of the record: the
 * medical status and the doctor's active medicine list. Food advice is given by
 * the dietician directly in the patient's care thread (never auto-generated).
 */
const router = Router();
router.use(requireAuth, requireDietician);

/**
 * A food-log review is due when the review interval has elapsed.
 *
 * The clinic-wide default applies unless this patient's record overrides it —
 * so a cadence set once in the doctor's panel covers every patient, and a
 * patient who needs closer watching can still be set apart.
 */
function reviewDue(p, defaultDays) {
  const interval = p.dietReviewIntervalDays ?? defaultDays;
  if (!interval) return false;
  const since = p.lastDietReviewAt ?? p.createdAt;
  return dayjs().diff(dayjs(since), 'day') >= interval;
}

/**
 * The patients this dietician may see.
 *
 * A clinic has one or two dieticians and hundreds of patients, so requiring an
 * explicit assignment per patient made the default "this patient has nutrition
 * care from nobody" and left it to the doctor to remember, one patient at a
 * time. The default is now the clinic's actual intent: the dietician covers
 * everyone.
 *
 * Assignment survives as a *restriction* rather than a grant — if any patient
 * has been explicitly assigned to this dietician, they see only those. That
 * keeps a lever for the day there is a second dietician or a locum, with no
 * schema change and nothing to migrate.
 */
async function scopeFilter(req) {
  const assigned = await PatientProfile.find({ assignedDietician: req.user._id }).select('user').lean();
  if (assigned.length === 0) return {};
  return { user: { $in: assigned.map((p) => p.user) } };
}

/** Guard: the id must be a patient this dietician may see. Returns the profile. */
async function requireAssigned(req) {
  const scope = await scopeFilter(req);
  const profile = await PatientProfile.findOne({ user: req.params.id, ...scope }).lean();
  if (!profile) throw notFound('Patient not found or not in your list');
  return profile;
}

/**
 * The dietician's day in one call: how many patients, how many reviews are due,
 * how many still have no plan, plus the two lists worth acting on.
 *
 * Computed server-side rather than assembled by the app from three endpoints:
 * the counts must agree with each other, and three round-trips over a clinic's
 * mobile connection is three chances to show a half-loaded dashboard.
 */
/**
 * Unread patient messages across the nutrition threads of [patientIds].
 *
 * `seenByClinicAt` is the clinic's single read marker rather than a per-user
 * one, so this is "nobody here has looked at it", not "this dietician has not".
 * For a caseload with one dietician on it those are the same thing; a badge
 * that quietly meant something narrower would be worse than this.
 */
async function unreadNutritionCount(patientIds) {
  if (patientIds.length === 0) return 0;
  const sessions = await ChatSession.find({ kind: 'nutrition', patient: { $in: patientIds } })
    .select('_id')
    .lean();
  if (sessions.length === 0) return 0;
  return ChatMessage.countDocuments({
    role: 'user',
    seenByClinicAt: null,
    session: { $in: sessions.map((s) => s._id) },
  });
}

router.get(
  '/dashboard',
  asyncHandler(async (req, res) => {
    const [profiles, settings] = await Promise.all([
      PatientProfile.find(await scopeFilter(req)).populate('user', 'name phone avatarAssetId isActive').lean(),
      getClinicSettings(),
    ]);
    const defaultDays = settings.dietReviewIntervalDays;
    const assigned = profiles.filter((p) => p.user && p.user.isActive !== false);
    const ids = assigned.map((p) => p.user._id);

    const [plans, recentLogs, unreadMessages] = await Promise.all([
      DietPlan.find({ patient: { $in: ids } }).select('patient updatedAt sharedAt').lean(),
      FoodLog.find({ patient: { $in: ids } })
        .sort({ createdAt: -1 })
        .limit(12)
        .populate('patient', 'name')
        .populate('photo', 'mimeType')
        .lean(),
      unreadNutritionCount(ids),
    ]);
    const planBy = new Map(plans.map((p) => [String(p.patient), p]));

    const brief = (p) => ({
      id: String(p.user._id),
      name: p.user.name,
      avatarUrl: p.user.avatarAssetId ? `/api/v1/uploads/${p.user.avatarAssetId}/raw` : null,
      riskBand: p.riskBand ?? 'low',
      diabetesType: p.diabetesType ?? null,
      reviewIntervalDays: p.dietReviewIntervalDays ?? defaultDays,
      lastReviewAt: p.lastDietReviewAt ?? null,
      // How long this has been waiting: since the last review if there was one,
      // otherwise since the record started. Reads correctly for both queues —
      // "review due 12d" and "no plan, 12d" are the same measurement.
      sinceDays: dayjs().diff(dayjs(p.lastDietReviewAt ?? p.createdAt), 'day'),
    });

    const due = assigned.filter((p) => reviewDue(p, defaultDays));
    // A plan that exists but was never sent is still work outstanding — the
    // patient cannot follow instructions they have not been given.
    const noPlan = assigned.filter((p) => {
      const plan = planBy.get(String(p.user._id));
      return !plan || !plan.sharedAt;
    });

    const weekAgo = dayjs().subtract(7, 'day');
    res.json({
      counts: {
        patients: assigned.length,
        // Real, not decorative: how many of those records were opened this
        // week. Rendered only when it is non-zero.
        newThisWeek: assigned.filter((p) => dayjs(p.createdAt).isAfter(weekAgo)).length,
        reviewsDue: due.length,
        plansMissing: noPlan.length,
        // Patient messages in the nutrition threads nobody at the clinic has
        // opened yet, scoped to this dietician's own caseload — a badge
        // counting somebody else's patients is a badge they cannot clear.
        unreadMessages,
      },
      reviewsDue: due.map(brief),
      plansMissing: noPlan.map(brief),
      recentLogs: recentLogs
        // Skip bogus logs whose "photo" is not an image (a mis-filed voice note).
        .filter((f) => f.patient && (!f.photo || (f.photo.mimeType ?? '').startsWith('image/')))
        .map((f) => ({
          id: String(f._id),
          patientId: String(f.patient._id),
          patientName: f.patient.name,
          mealType: f.mealType,
          note: f.note ?? '',
          photoUrl: f.photo ? `/api/v1/uploads/${f.photo._id}/raw` : null,
          createdAt: f.createdAt,
        })),
    });
  }),
);

/** The dietician's worklist: patients assigned to them. */
router.get(
  '/patients',
  asyncHandler(async (req, res) => {
    const [profiles, settings] = await Promise.all([
      PatientProfile.find(await scopeFilter(req))
        .populate('user', 'name phone avatarAssetId isActive dateOfBirth')
        .sort({ updatedAt: -1 })
        .lean(),
      getClinicSettings(),
    ]);
    const defaultDays = settings.dietReviewIntervalDays;

    const items = profiles
      .filter((p) => p.user && p.user.isActive !== false)
      .map((p) => ({
        id: String(p.user._id),
        name: p.user.name,
        phone: p.user.phone,
        avatarUrl: p.user.avatarAssetId ? `/api/v1/uploads/${p.user.avatarAssetId}/raw` : null,
        diabetesType: p.diabetesType ?? null,
        riskBand: p.riskBand ?? 'low',
        reviewIntervalDays: p.dietReviewIntervalDays ?? defaultDays,
        lastReviewAt: p.lastDietReviewAt ?? null,
        reviewDue: reviewDue(p, defaultDays),
        // Energy and protein targets are set by age as much as by weight, so
        // the worklist carries it rather than making the dietician open each
        // record to find out who they are planning for.
        dateOfBirth: p.user.dateOfBirth ?? null,
      }));

    res.json({ items });
  }),
);

/** Nutrition view of one patient: medical status + the doctor's medicine list. */
router.get(
  '/patients/:id/overview',
  asyncHandler(async (req, res) => {
    const profile = await requireAssigned(req);
    const user = await User.findById(req.params.id)
      .select('name phone gender dateOfBirth language avatarAssetId')
      .lean();
    if (!user) throw notFound('Patient not found');

    // The full clinical picture, live from the doctor's own record — medicines,
    // advice, vitals, the uploaded reports. A dietician planning around metformin
    // needs to know it was stopped last week; a pending HbA1c is the difference
    // between "your control is fine" and a number nobody has yet.
    const [meds, prescriptions, labResults, latestHba1c, vitals, latestGlucose] = await Promise.all([
      Medication.find({ patient: req.params.id, isActive: true })
        .select('name strength dose schedule instructions')
        .lean(),
      Prescription.find({ patient: req.params.id, isActive: true })
        .sort({ issuedOn: -1 })
        .select('labTestsAdvised generalAdvice diagnosis issuedOn followUpOn doctor')
        .populate('doctor', 'name')
        .lean(),
      LabResult.find({ patient: req.params.id })
        .sort({ createdAt: -1 })
        .limit(10)
        .populate('photo', 'mimeType originalName sizeBytes')
        .lean(),
      Hba1cRecord.findOne({ patient: req.params.id }).sort({ testedOn: -1 }).lean(),
      VitalRecord.find({ patient: req.params.id }).sort({ recordedAt: -1 }).limit(40).lean(),
      GlucoseReading.findOne({ patient: req.params.id }).sort({ measuredAt: -1 }).lean(),
    ]);

    const advised = [...new Set(prescriptions.flatMap((p) => p.labTestsAdvised ?? []).filter(Boolean))];
    const reported = new Set(labResults.map((r) => r.testName.toLowerCase()));

    // Each measurement shown as its OWN most-recent real reading, with the date
    // it was actually taken — never blended, never invented. A field the patient
    // has never recorded is simply absent: honest emptiness over a fake zero.
    const latest = (field) => {
      const rec = vitals.find((v) => v[field] != null);
      return rec ? { value: rec[field], at: rec.recordedAt } : null;
    };
    const bpRec = vitals.find((v) => v.systolic != null || v.diastolic != null);
    const weight = latest('weightKg');
    const heightCm = profile.heightCm ?? null;
    const bmi = weight && heightCm ? Number((weight.value / (heightCm / 100) ** 2).toFixed(1)) : null;

    res.json({
      patient: {
        id: String(user._id),
        name: user.name,
        phone: user.phone,
        avatarUrl: user.avatarAssetId ? `/api/v1/uploads/${user.avatarAssetId}/raw` : null,
        gender: user.gender ?? null,
        dateOfBirth: user.dateOfBirth ?? null,
        language: user.language ?? 'en',
      },
      medical: {
        diabetesType: profile.diabetesType ?? null,
        riskBand: profile.riskBand ?? 'low',
        heightCm,
        diagnosedOn: profile.diagnosedOn ?? null,
        chiefComplaint: profile.chiefComplaint ?? null,
        allergies: profile.allergies ?? [],
        targets: profile.targets ?? {},
      },
      // Latest real vitals/measurements, each dated. Absent = never recorded.
      vitals: {
        bloodPressure: bpRec
          ? { systolic: bpRec.systolic ?? null, diastolic: bpRec.diastolic ?? null, flag: bpRec.flag ?? null, at: bpRec.recordedAt }
          : null,
        pulse: latest('pulse'),
        spo2: latest('spo2'),
        weightKg: weight,
        waistCm: latest('waistCm'),
        temperatureC: latest('temperatureC'),
        bmi,
        glucose: latestGlucose
          ? { valueMgDl: latestGlucose.valueMgDl, context: latestGlucose.context ?? null, flag: latestGlucose.flag ?? null, at: latestGlucose.measuredAt }
          : null,
      },
      medications: meds.map((m) => ({
        id: String(m._id),
        name: m.name,
        strength: m.strength ?? '',
        dose: m.dose ?? '',
        instructions: m.instructions ?? '',
        times: (m.schedule ?? []).map((s) => s.time).filter(Boolean),
      })),
      // The doctor's advice + diagnosis over time, newest first — so the dietician
      // plans with the clinical reasoning in view, not just the medicine list.
      advice: prescriptions
        .filter((p) => (p.generalAdvice && p.generalAdvice.trim()) || (p.diagnosis && p.diagnosis.length))
        .map((p) => ({
          id: String(p._id),
          issuedOn: p.issuedOn,
          diagnosis: p.diagnosis ?? [],
          generalAdvice: p.generalAdvice ?? '',
          followUpOn: p.followUpOn ?? null,
          doctorName: p.doctor?.name ?? null,
        })),
      labTests: {
        // Whether a result is back matters more than the list itself: an
        // advised-but-missing test is why a plan may be built on stale numbers.
        advised: advised.map((name) => ({ name, reported: reported.has(name.toLowerCase()) })),
        // The uploaded reports themselves — summary, out-of-range analytes, the
        // file to open — the SAME flat shape the doctor's panel sends, so the
        // dietician reuses the doctor's LabReport model and "out of range" reads
        // identically in both panels.
        recent: labResults.map((r) => {
          const asset = r.photo && typeof r.photo === 'object' ? r.photo : null;
          const photoId = asset ? asset._id : r.photo;
          return {
            id: String(r._id),
            testName: r.testName,
            note: r.note ?? '',
            photoUrl: photoId ? `/api/v1/uploads/${photoId}/raw` : null,
            mimeType: asset?.mimeType ?? null,
            originalName: asset?.originalName ?? null,
            analysisStatus: r.analysis?.status ?? null,
            analysisSummary: r.analysis?.summary ?? null,
            hba1cPercent: r.analysis?.hba1cPercent ?? null,
            abnormal: r.analysis?.abnormal ?? [],
            analytes: buildAnalytes(r.analysis),
            testedOn: r.analysis?.testedOn ?? null,
            createdAt: r.createdAt,
          };
        }),
        latestHba1c: latestHba1c
          ? { percentage: latestHba1c.percentage, testedOn: latestHba1c.testedOn }
          : null,
      },
      reviewIntervalDays: profile.dietReviewIntervalDays ?? null,
      lastReviewAt: profile.lastDietReviewAt ?? null,
    });
  }),
);

/** The patient's food log for the dietician to review. */
router.get(
  '/patients/:id/food-log',
  asyncHandler(async (req, res) => {
    await requireAssigned(req);
    const items = await FoodLog.find({ patient: req.params.id })
      .sort({ createdAt: -1 })
      .limit(100)
      .populate('photo', 'mimeType')
      .lean();
    res.json({
      items: items
          .filter((f) => !f.photo || (f.photo.mimeType ?? '').startsWith('image/'))
          .map((f) => ({
            id: String(f._id),
            mealType: f.mealType,
            note: f.note ?? '',
            photoUrl: f.photo ? `/api/v1/uploads/${f.photo._id}/raw` : null,
            createdAt: f.createdAt,
          })),
    });
  }),
);

/** The patient's current diet plan, or null if none has been written yet. */
router.get(
  '/patients/:id/diet',
  asyncHandler(async (req, res) => {
    await requireAssigned(req);
    const plan = await DietPlan.findOne({ patient: req.params.id })
      .populate('dietician', 'name')
      .lean();
    res.json({ plan: plan ? serialisePlan(plan) : null });
  }),
);

/**
 * Write or rewrite the plan. Upsert rather than versioned history: the patient
 * needs one current answer to "what do I eat", and a dietician correcting a
 * portion size should not create a second document the patient might find.
 */
router.put(
  '/patients/:id/diet',
  validate({
    body: z.object({
      goal: z.string().trim().max(500).optional().default(''),
      meals: z
        .array(
          z.object({
            name: z.string().trim().min(1).max(60),
            time: z.string().trim().max(40).optional().default(''),
            items: z.array(z.string().trim().max(200)).max(20).default([]),
            notes: z.string().trim().max(500).optional().default(''),
          }),
        )
        .max(10)
        .default([]),
      avoid: z.array(z.string().trim().max(120)).max(30).default([]),
      notes: z.string().trim().max(2000).optional().default(''),
    }),
  }),
  audit('update', 'DietPlan'),
  asyncHandler(async (req, res) => {
    await requireAssigned(req);

    // Drop meals the dietician left blank rather than storing empty rows the
    // patient would see as gaps in their day.
    const meals = req.body.meals
      .map((m) => ({ ...m, items: m.items.filter((i) => i.trim().length > 0) }))
      .filter((m) => m.items.length > 0 || m.notes.trim().length > 0);

    const plan = await DietPlan.findOneAndUpdate(
      { patient: req.params.id },
      {
        patient: req.params.id,
        dietician: req.user._id,
        goal: req.body.goal,
        meals,
        avoid: req.body.avoid.filter((a) => a.trim().length > 0),
        notes: req.body.notes,
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    );

    res.json({ plan: serialisePlan({ ...plan.toObject(), dietician: { name: req.user.name } }) });
  }),
);

/**
 * Send the plan into the patient's care thread.
 *
 * Deliberately a separate action from saving. A dietician mid-edit should not
 * be notifying the patient on every keystroke, and a plan only counts as given
 * once the patient has actually been handed it.
 */
router.post(
  '/patients/:id/diet/send',
  audit('create', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    await requireAssigned(req);
    const plan = await DietPlan.findOne({ patient: req.params.id }).lean();
    if (!plan) throw notFound('Write a plan before sending it');

    const content = formatPlan(plan, req.user.name);
    const message = await postToCareThread(req.params.id, req.user, content);

    await DietPlan.updateOne({ _id: plan._id }, { sharedAt: new Date() });
    await PatientProfile.updateOne({ user: req.params.id }, { lastDietReviewAt: new Date() });
    notifyPatientOfClinicianReply(req.params.id, req.user, content).catch(() => {});

    res.status(201).json({ id: String(message._id) });
  }),
);

/** The care conversation with the patient (shared with the assistant/doctor). */
router.get(
  '/patients/:id/thread',
  asyncHandler(async (req, res) => {
    await requireAssigned(req);
    const session = await ChatSession.findOne({
      patient: req.params.id,
      kind: 'nutrition',
      isArchived: false,
    }).sort({ lastMessageAt: -1 });
    if (!session) return res.json({ items: [] });

    const messages = await ChatMessage.find({ session: session._id })
      .sort({ seq: 1 })
      .limit(300)
      .populate('sender', 'name avatarAssetId')
      .populate('attachments', 'kind mimeType transcript originalName sizeBytes')
      .populate('replyTo', 'content role')
      .lean();

    res.json({
      items: messages.map((m) => {
        // Deleted for everyone: a tombstone, same as the patient/doctor threads.
        if (m.deletedForEveryoneAt) {
          return {
            id: String(m._id),
            role: m.role,
            content: '',
            attachments: [],
            senderName: m.sender?.name ?? null,
            deletedForEveryone: true,
            pinned: false,
            replyToId: null,
            replyPreview: null,
            createdAt: m.createdAt,
          };
        }
        return {
          id: String(m._id),
          role: m.role,
          content: m.content ?? '',
          deletedForEveryone: false,
          // Pin / reply state, so the dietician's screen can show and act on
          // them the same way the patient and doctor threads do.
          pinned: Boolean(m.pinnedAt),
          replyToId: m.replyTo ? String(m.replyTo._id ?? m.replyTo) : null,
          replyPreview:
            m.replyTo && typeof m.replyTo === 'object' && m.replyTo.content != null
              ? { content: String(m.replyTo.content).slice(0, 160), role: m.replyTo.role ?? null }
              : null,
          // The same shape the patient's own thread sends. Bare ids left the
          // dietician's screen unable to tell a food photo from a voice note
          // from a PDF, so it rendered all three as the words "1 attachment" —
          // in the one conversation whose whole point is looking at food.
          attachments: (m.attachments ?? []).map((a) => {
            const id = (a?._id ?? a).toString?.() ?? a;
            return {
              id,
              url: `/api/v1/uploads/${id}/raw`,
              kind: a?.kind ?? null,
              mimeType: a?.mimeType ?? null,
              originalName: a?.originalName ?? null,
              sizeBytes: a?.sizeBytes ?? null,
              transcript: a?.transcript ?? null,
            };
          }),
          senderName: m.sender?.name ?? null,
          senderAvatarUrl: m.sender?.avatarAssetId
            ? `/api/v1/uploads/${m.sender.avatarAssetId}/raw`
            : null,
          createdAt: m.createdAt,
        };
      }),
    });
  }),
);

/** The dietician replies to the patient — lands in the patient's care thread. */
router.post(
  '/patients/:id/message',
  validate({
    body: z
      .object({
        content: z.string().trim().max(4000).optional().default(''),
        attachments: z.array(z.string()).max(5).default([]),
        // Threaded reply: the message this one answers.
        replyTo: z.string().optional(),
      })
      .refine((b) => b.content.trim().length > 0 || b.attachments.length > 0, {
        message: 'Add a message or attach a photo',
        path: ['content'],
      }),
  }),
  audit('create', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    await requireAssigned(req);

    const message = await postToCareThread(
      req.params.id,
      req.user,
      req.body.content,
      req.body.attachments,
      req.body.replyTo,
    );

    // Mark the food-log review as done for this cycle, and let the patient know.
    await PatientProfile.updateOne({ user: req.params.id }, { lastDietReviewAt: new Date() });
    notifyPatientOfClinicianReply(req.params.id, req.user, req.body.content).catch(() => {});

    res.status(201).json({ id: String(message._id) });
  }),
);

/**
 * Append a dietician message to the patient's care thread, creating the session
 * if this is the first thing anyone has said. Shared by the reply box and by
 * "send plan" so both land in the same thread with the same role and sequence.
 */
async function postToCareThread(patientId, sender, content, attachments = [], replyTo) {
  let session = await ChatSession.findOne({
    patient: patientId,
    kind: 'nutrition',
    isArchived: false,
  }).sort({ lastMessageAt: -1 });
  if (!session) {
    const patient = await User.findById(patientId).select('language').lean();
    session = await ChatSession.create({
      patient: patientId,
      kind: 'nutrition',
      language: patient?.language ?? 'en',
      title: 'Nutrition',
    });
  }

  const last = await ChatMessage.findOne({ session: session._id }).sort({ seq: -1 }).select('seq').lean();
  const message = await ChatMessage.create({
    session: session._id,
    patient: patientId,
    seq: (last?.seq ?? -1) + 1,
    role: 'dietician',
    sender: sender._id,
    content,
    language: session.language,
    attachments,
    replyTo: replyTo || undefined,
  });

  await ChatSession.findByIdAndUpdate(session._id, {
    lastMessageAt: message.createdAt,
    $inc: { messageCount: 1 },
  });

  return message;
}

function serialisePlan(plan) {
  return {
    goal: plan.goal ?? '',
    meals: (plan.meals ?? []).map((m) => ({
      name: m.name,
      time: m.time ?? '',
      items: m.items ?? [],
      notes: m.notes ?? '',
    })),
    avoid: plan.avoid ?? [],
    notes: plan.notes ?? '',
    dieticianName: plan.dietician?.name ?? null,
    sharedAt: plan.sharedAt ?? null,
    updatedAt: plan.updatedAt ?? null,
  };
}

/**
 * Render the plan as the patient will read it in their thread.
 *
 * Plain text with headings rather than a card the app has to know how to draw:
 * it survives translation, it is copyable, and it still makes sense if the
 * patient screenshots it for someone at home who does the cooking.
 */
function formatPlan(plan, dieticianName) {
  const lines = [`Your diet plan — from ${dieticianName}`];
  if (plan.goal) lines.push('', `Goal: ${plan.goal}`);

  for (const meal of plan.meals ?? []) {
    lines.push('', meal.time ? `${meal.name} (${meal.time})` : meal.name);
    for (const item of meal.items ?? []) lines.push(`• ${item}`);
    if (meal.notes) lines.push(meal.notes);
  }

  if (plan.avoid?.length) {
    lines.push('', 'Best avoided:');
    for (const item of plan.avoid) lines.push(`• ${item}`);
  }
  if (plan.notes) lines.push('', plan.notes);

  lines.push('', 'Ask me here if anything does not suit you — we can change it.');
  return lines.join('\n');
}

export default router;

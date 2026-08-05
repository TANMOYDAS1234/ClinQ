import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, requireDietician } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler, notFound } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { User } from '../models/User.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { Medication } from '../models/Medication.js';
import { FoodLog } from '../models/FoodLog.js';
import { ChatSession } from '../models/ChatSession.js';
import { ChatMessage } from '../models/ChatMessage.js';
import { DietPlan } from '../models/DietPlan.js';
import { notifyPatientOfClinicianReply } from '../services/notifications.js';
import { dayjs } from '../utils/clinicTime.js';

/**
 * The dietician panel API. A dietician only ever sees the patients a doctor has
 * assigned to them, and only the nutrition-relevant slice of the record: the
 * medical status and the doctor's active medicine list. Food advice is given by
 * the dietician directly in the patient's care thread (never auto-generated).
 */
const router = Router();
router.use(requireAuth, requireDietician);

/** A food-log review is due when the doctor-set interval has elapsed. */
function reviewDue(p) {
  if (!p.dietReviewIntervalDays) return false;
  const since = p.lastDietReviewAt ?? p.createdAt;
  return dayjs().diff(dayjs(since), 'day') >= p.dietReviewIntervalDays;
}

/** Guard: the patient must be assigned to THIS dietician. Returns the profile. */
async function requireAssigned(req) {
  const profile = await PatientProfile.findOne({
    user: req.params.id,
    assignedDietician: req.user._id,
  }).lean();
  if (!profile) throw notFound('Patient not found or not assigned to you');
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
router.get(
  '/dashboard',
  asyncHandler(async (req, res) => {
    const profiles = await PatientProfile.find({ assignedDietician: req.user._id })
      .populate('user', 'name phone avatarAssetId')
      .lean();
    const assigned = profiles.filter((p) => p.user);
    const ids = assigned.map((p) => p.user._id);

    const [plans, recentLogs] = await Promise.all([
      DietPlan.find({ patient: { $in: ids } }).select('patient updatedAt sharedAt').lean(),
      FoodLog.find({ patient: { $in: ids } })
        .sort({ createdAt: -1 })
        .limit(12)
        .populate('patient', 'name')
        .lean(),
    ]);
    const planBy = new Map(plans.map((p) => [String(p.patient), p]));

    const brief = (p) => ({
      id: String(p.user._id),
      name: p.user.name,
      avatarAssetId: p.user.avatarAssetId ? String(p.user.avatarAssetId) : null,
      riskBand: p.riskBand ?? 'low',
      diabetesType: p.diabetesType ?? null,
      reviewIntervalDays: p.dietReviewIntervalDays ?? null,
      lastReviewAt: p.lastDietReviewAt ?? null,
    });

    const due = assigned.filter(reviewDue);
    // A plan that exists but was never sent is still work outstanding — the
    // patient cannot follow instructions they have not been given.
    const noPlan = assigned.filter((p) => {
      const plan = planBy.get(String(p.user._id));
      return !plan || !plan.sharedAt;
    });

    res.json({
      counts: {
        patients: assigned.length,
        reviewsDue: due.length,
        plansMissing: noPlan.length,
      },
      reviewsDue: due.map(brief),
      plansMissing: noPlan.map(brief),
      recentLogs: recentLogs
        .filter((f) => f.patient)
        .map((f) => ({
          id: String(f._id),
          patientId: String(f.patient._id),
          patientName: f.patient.name,
          mealType: f.mealType,
          note: f.note ?? '',
          photoUrl: f.photo ? `/api/v1/uploads/${f.photo}/raw` : null,
          createdAt: f.createdAt,
        })),
    });
  }),
);

/** The dietician's worklist: patients assigned to them. */
router.get(
  '/patients',
  asyncHandler(async (req, res) => {
    const profiles = await PatientProfile.find({ assignedDietician: req.user._id })
      .populate('user', 'name phone avatarAssetId')
      .sort({ updatedAt: -1 })
      .lean();

    const items = profiles
      .filter((p) => p.user)
      .map((p) => ({
        id: String(p.user._id),
        name: p.user.name,
        phone: p.user.phone,
        avatarAssetId: p.user.avatarAssetId ? String(p.user.avatarAssetId) : null,
        diabetesType: p.diabetesType ?? null,
        riskBand: p.riskBand ?? 'low',
        reviewIntervalDays: p.dietReviewIntervalDays ?? null,
        lastReviewAt: p.lastDietReviewAt ?? null,
        reviewDue: reviewDue(p),
      }));

    res.json({ items });
  }),
);

/** Nutrition view of one patient: medical status + the doctor's medicine list. */
router.get(
  '/patients/:id/overview',
  asyncHandler(async (req, res) => {
    const profile = await requireAssigned(req);
    const user = await User.findById(req.params.id).select('name phone gender dateOfBirth language').lean();
    if (!user) throw notFound('Patient not found');

    const meds = await Medication.find({ patient: req.params.id, isActive: true })
      .select('name strength dose schedule')
      .lean();

    res.json({
      patient: {
        id: String(user._id),
        name: user.name,
        phone: user.phone,
        gender: user.gender ?? null,
        language: user.language ?? 'en',
      },
      medical: {
        diabetesType: profile.diabetesType ?? null,
        riskBand: profile.riskBand ?? 'low',
        heightCm: profile.heightCm ?? null,
        allergies: profile.allergies ?? [],
        targets: profile.targets ?? {},
      },
      medications: meds.map((m) => ({
        id: String(m._id),
        name: m.name,
        strength: m.strength ?? '',
        dose: m.dose ?? '',
        times: (m.schedule ?? []).map((s) => s.time).filter(Boolean),
      })),
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
    const items = await FoodLog.find({ patient: req.params.id }).sort({ createdAt: -1 }).limit(100).lean();
    res.json({
      items: items.map((f) => ({
        id: String(f._id),
        mealType: f.mealType,
        note: f.note ?? '',
        photoUrl: f.photo ? `/api/v1/uploads/${f.photo}/raw` : null,
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
    const session = await ChatSession.findOne({ patient: req.params.id, isArchived: false }).sort({ lastMessageAt: -1 });
    if (!session) return res.json({ items: [] });

    const messages = await ChatMessage.find({ session: session._id })
      .sort({ seq: 1 })
      .limit(300)
      .populate('sender', 'name')
      .lean();

    res.json({
      items: messages.map((m) => ({
        id: String(m._id),
        role: m.role,
        content: m.content ?? '',
        attachments: (m.attachments ?? []).map(String),
        senderName: m.sender?.name ?? null,
        createdAt: m.createdAt,
      })),
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
      })
      .refine((b) => b.content.trim().length > 0 || b.attachments.length > 0, {
        message: 'Add a message or attach a photo',
        path: ['content'],
      }),
  }),
  audit('create', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    await requireAssigned(req);

    const message = await postToCareThread(req.params.id, req.user, req.body.content, req.body.attachments);

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
async function postToCareThread(patientId, sender, content, attachments = []) {
  let session = await ChatSession.findOne({ patient: patientId, isArchived: false }).sort({ lastMessageAt: -1 });
  if (!session) {
    const patient = await User.findById(patientId).select('language').lean();
    session = await ChatSession.create({
      patient: patientId,
      language: patient?.language ?? 'en',
      title: 'Message from your dietician',
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

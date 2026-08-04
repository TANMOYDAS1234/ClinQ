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

    let session = await ChatSession.findOne({ patient: req.params.id, isArchived: false }).sort({ lastMessageAt: -1 });
    if (!session) {
      const patient = await User.findById(req.params.id).select('language').lean();
      session = await ChatSession.create({
        patient: req.params.id,
        language: patient?.language ?? 'en',
        title: 'Message from your dietician',
      });
    }

    const last = await ChatMessage.findOne({ session: session._id }).sort({ seq: -1 }).select('seq').lean();
    const message = await ChatMessage.create({
      session: session._id,
      patient: req.params.id,
      seq: (last?.seq ?? -1) + 1,
      role: 'dietician',
      sender: req.user._id,
      content: req.body.content,
      language: session.language,
      attachments: req.body.attachments,
    });

    await ChatSession.findByIdAndUpdate(session._id, {
      lastMessageAt: message.createdAt,
      $inc: { messageCount: 1 },
    });

    // Mark the food-log review as done for this cycle, and let the patient know.
    await PatientProfile.updateOne({ user: req.params.id }, { lastDietReviewAt: new Date() });
    notifyPatientOfClinicianReply(req.params.id, req.user, req.body.content).catch(() => {});

    res.status(201).json({ id: String(message._id) });
  }),
);

export default router;

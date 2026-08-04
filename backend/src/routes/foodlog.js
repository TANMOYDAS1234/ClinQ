import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, resolvePatientScope } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { FoodLog, MEAL_TYPES } from '../models/FoodLog.js';

/**
 * The patient's food log — meals they record (a photo and/or a note) for their
 * dietician to review. Mounted at /patients/:patientId/food-log; the patient
 * uses `me`, a clinician a real id.
 */
const router = Router({ mergeParams: true });
router.use(requireAuth, resolvePatientScope);

export function serialiseFoodLog(f) {
  return {
    id: String(f._id),
    mealType: f.mealType,
    note: f.note ?? '',
    photoUrl: f.photo ? `/api/v1/uploads/${f.photo}/raw` : null,
    createdAt: f.createdAt,
  };
}

router.get(
  '/',
  audit('read', 'FoodLog'),
  asyncHandler(async (req, res) => {
    const items = await FoodLog.find({ patient: req.patientId }).sort({ createdAt: -1 }).limit(100).lean();
    res.json({ items: items.map(serialiseFoodLog) });
  }),
);

router.post(
  '/',
  validate({
    body: z
      .object({
        mealType: z.enum(MEAL_TYPES).default('other'),
        note: z.string().trim().max(1000).optional().default(''),
        photo: z.string().optional(),
      })
      .refine((b) => b.note.trim().length > 0 || b.photo, { message: 'Add a note or a photo', path: ['note'] }),
  }),
  audit('create', 'FoodLog'),
  asyncHandler(async (req, res) => {
    const entry = await FoodLog.create({
      patient: req.patientId,
      mealType: req.body.mealType,
      note: req.body.note,
      photo: req.body.photo || undefined,
    });
    res.status(201).json({ entry: serialiseFoodLog(entry) });
  }),
);

export default router;

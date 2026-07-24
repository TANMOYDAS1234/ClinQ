import { Router } from 'express';
import dayjs from 'dayjs';
import { z } from 'zod';
import { requireAuth, resolvePatientScope } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { Medication, MED_FORMS } from '../models/Medication.js';
import { MedicationLog } from '../models/MedicationLog.js';
import { computeAdherence } from '../services/analytics.js';

const router = Router({ mergeParams: true });
router.use(requireAuth, resolvePatientScope);

const scheduleSlot = z.object({
  time: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Time must be HH:mm'),
  relationToMeal: z.enum(['before_meal', 'after_meal', 'with_meal', 'any']).default('any'),
});

const medicationSchema = z.object({
  name: z.string().trim().min(1).max(160),
  genericName: z.string().max(160).optional(),
  form: z.enum(MED_FORMS).default('tablet'),
  strength: z.string().max(60).optional(),
  dose: z.string().max(60).optional(),
  schedule: z.array(scheduleSlot).min(1, 'At least one dose time is required').max(8),
  daysOfWeek: z.array(z.number().int().min(0).max(6)).max(7).default([]),
  startDate: z.coerce.date().default(() => new Date()),
  endDate: z.coerce.date().optional(),
  instructions: z.string().max(600).optional(),
});

router.get(
  '/',
  validate({ query: z.object({ includeInactive: z.coerce.boolean().default(false) }) }),
  audit('read', 'Medication'),
  asyncHandler(async (req, res) => {
    const filter = { patient: req.patientId };
    if (!q(req).includeInactive) filter.isActive = true;
    const items = await Medication.find(filter).sort({ createdAt: -1 }).lean();
    res.json({ items: items.map(serialise) });
  }),
);

router.post(
  '/',
  validate({ body: medicationSchema }),
  audit('create', 'Medication'),
  asyncHandler(async (req, res) => {
    const med = await Medication.create({
      ...req.body,
      patient: req.patientId,
      prescribedBy: req.user.role === 'patient' ? undefined : req.user._id,
    });
    res.status(201).json({ medication: serialise(med) });
  }),
);

router.patch(
  '/:id',
  validate({ body: medicationSchema.partial().extend({ isActive: z.boolean().optional() }) }),
  audit('update', 'Medication'),
  asyncHandler(async (req, res) => {
    const med = await Medication.findOneAndUpdate(
      { _id: req.params.id, patient: req.patientId },
      { $set: req.body },
      { new: true, runValidators: true },
    );
    if (!med) throw notFound('Medication not found');
    res.json({ medication: serialise(med) });
  }),
);

router.delete(
  '/:id',
  audit('update', 'Medication'),
  asyncHandler(async (req, res) => {
    // Soft delete: adherence history for past doses must remain interpretable.
    const med = await Medication.findOneAndUpdate(
      { _id: req.params.id, patient: req.patientId },
      { isActive: false, endDate: new Date() },
    );
    if (!med) throw notFound('Medication not found');
    res.status(204).end();
  }),
);

/**
 * Today's dose slots, expanded from each medication's schedule and joined
 * against what has already been logged.
 */
router.get(
  '/schedule/today',
  validate({ query: z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() }) }),
  asyncHandler(async (req, res) => {
    const day = q(req).date ? dayjs(q(req).date) : dayjs();
    const dayStart = day.startOf('day');
    const dayEnd = day.endOf('day');

    const meds = await Medication.find({
      patient: req.patientId,
      isActive: true,
      startDate: { $lte: dayEnd.toDate() },
      $or: [{ endDate: null }, { endDate: { $gte: dayStart.toDate() } }],
    }).lean();

    const logs = await MedicationLog.find({
      patient: req.patientId,
      scheduledFor: { $gte: dayStart.toDate(), $lte: dayEnd.toDate() },
    }).lean();

    const logKey = (medId, when) => `${medId}|${dayjs(when).format('HH:mm')}`;
    const logMap = new Map(logs.map((l) => [logKey(l.medication, l.scheduledFor), l]));

    const now = dayjs();
    const slots = [];

    for (const med of meds) {
      if (med.daysOfWeek?.length && !med.daysOfWeek.includes(day.day())) continue;

      for (const slot of med.schedule ?? []) {
        const [hh, mm] = slot.time.split(':').map(Number);
        const scheduledFor = day.hour(hh).minute(mm).second(0).millisecond(0);
        const log = logMap.get(logKey(med._id, scheduledFor.toDate()));

        // A dose is only "missed" once a grace period has elapsed, so the UI
        // does not scold a patient for being ten minutes late.
        const overdue = now.diff(scheduledFor, 'minute') > 120;
        const status = log ? log.status : overdue ? 'missed' : 'pending';

        slots.push({
          medicationId: med._id,
          name: med.name,
          form: med.form,
          strength: med.strength ?? null,
          dose: med.dose ?? null,
          time: slot.time,
          scheduledFor: scheduledFor.toDate(),
          relationToMeal: slot.relationToMeal,
          instructions: med.instructions ?? null,
          status,
          logId: log?._id ?? null,
        });
      }
    }

    slots.sort((a, b) => a.time.localeCompare(b.time));
    res.json({ date: day.format('YYYY-MM-DD'), slots });
  }),
);

router.post(
  '/:id/log',
  validate({
    body: z.object({
      scheduledFor: z.coerce.date(),
      status: z.enum(['taken', 'skipped', 'missed']),
      takenAt: z.coerce.date().optional(),
      actualDose: z.string().max(60).optional(),
      unitsAdministered: z.number().min(0).max(500).optional(),
      injectionSite: z
        .enum(['abdomen', 'left_thigh', 'right_thigh', 'left_arm', 'right_arm', 'buttock', 'other'])
        .optional(),
      skipReason: z.string().max(300).optional(),
    }),
  }),
  audit('create', 'MedicationLog'),
  asyncHandler(async (req, res) => {
    const med = await Medication.findOne({ _id: req.params.id, patient: req.patientId });
    if (!med) throw notFound('Medication not found');

    // Upsert on (medication, scheduledFor) so a flaky connection retrying the
    // same tap does not create duplicate doses.
    const log = await MedicationLog.findOneAndUpdate(
      { medication: med._id, scheduledFor: req.body.scheduledFor },
      {
        $set: {
          ...req.body,
          patient: req.patientId,
          medication: med._id,
          takenAt: req.body.status === 'taken' ? (req.body.takenAt ?? new Date()) : undefined,
        },
      },
      { new: true, upsert: true, setDefaultsOnInsert: true },
    );

    res.status(201).json({ log: serialiseLog(log) });
  }),
);

router.get(
  '/adherence',
  validate({ query: z.object({ days: z.coerce.number().int().min(1).max(365).default(30) }) }),
  asyncHandler(async (req, res) => {
    res.json(await computeAdherence(req.patientId, { days: q(req).days }));
  }),
);

const serialise = (m) => ({
  id: m._id,
  name: m.name,
  genericName: m.genericName ?? null,
  form: m.form,
  strength: m.strength ?? null,
  dose: m.dose ?? null,
  schedule: (m.schedule ?? []).map((s) => ({ time: s.time, relationToMeal: s.relationToMeal })),
  daysOfWeek: m.daysOfWeek ?? [],
  startDate: m.startDate,
  endDate: m.endDate ?? null,
  isActive: m.isActive,
  instructions: m.instructions ?? null,
});

const serialiseLog = (l) => ({
  id: l._id,
  medicationId: l.medication,
  scheduledFor: l.scheduledFor,
  status: l.status,
  takenAt: l.takenAt ?? null,
  unitsAdministered: l.unitsAdministered ?? null,
  injectionSite: l.injectionSite ?? null,
  skipReason: l.skipReason ?? null,
});

export default router;

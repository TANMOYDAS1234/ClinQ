import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, resolvePatientScope } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { LabResult } from '../models/LabResult.js';
import { Prescription } from '../models/Prescription.js';

/**
 * The patient's lab tests: the tests the doctor advised (pulled from active
 * prescriptions) and the reports the patient has uploaded against them.
 * Mounted at /patients/:patientId/lab-tests.
 */
const router = Router({ mergeParams: true });
router.use(requireAuth, resolvePatientScope);

function serialiseResult(r) {
  return {
    id: String(r._id),
    testName: r.testName,
    note: r.note ?? '',
    photoUrl: r.photo ? `/api/v1/uploads/${r.photo}/raw` : null,
    createdAt: r.createdAt,
  };
}

router.get(
  '/',
  audit('read', 'LabResult'),
  asyncHandler(async (req, res) => {
    const [prescriptions, results] = await Promise.all([
      Prescription.find({ patient: req.patientId, isActive: true }).select('labTestsAdvised').lean(),
      LabResult.find({ patient: req.patientId }).sort({ createdAt: -1 }).limit(100).lean(),
    ]);
    const advised = [...new Set(prescriptions.flatMap((p) => p.labTestsAdvised ?? []).filter(Boolean))];
    res.json({ advised, results: results.map(serialiseResult) });
  }),
);

router.post(
  '/',
  validate({
    body: z
      .object({
        testName: z.string().trim().min(1).max(200),
        note: z.string().trim().max(1000).optional().default(''),
        photo: z.string().optional(),
      })
      .refine((b) => Boolean(b.photo) || b.note.trim().length > 0, { message: 'Add a photo or a note', path: ['photo'] }),
  }),
  audit('create', 'LabResult'),
  asyncHandler(async (req, res) => {
    const entry = await LabResult.create({
      patient: req.patientId,
      testName: req.body.testName,
      note: req.body.note,
      photo: req.body.photo || undefined,
    });
    res.status(201).json({ result: serialiseResult(entry) });
  }),
);

export default router;

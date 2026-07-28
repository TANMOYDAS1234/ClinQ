import { Router } from 'express';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler, badRequest, forbidden } from '../middleware/errors.js';
import { User, ROLES } from '../models/User.js';
import { notifyIncomingCall } from '../services/notifications.js';

const router = Router();
router.use(requireAuth);

/**
 * Ring the other party of a patient↔clinic call. The caller has already joined
 * the Jitsi room; this pushes an incoming-call alert to the other side so they
 * can join the same room. Room name is derived from the patient id, so both
 * sides compute the same one.
 */
router.post(
  '/ring',
  validate({
    body: z.object({
      patientId: z.string().optional(),
      video: z.boolean().default(true),
    }),
  }),
  asyncHandler(async (req, res) => {
    const isPatient = req.user.role === ROLES.PATIENT;
    const patientId = isPatient ? req.user._id.toString() : req.body.patientId;
    if (!patientId) throw badRequest('patientId is required');
    if (isPatient && patientId !== req.user._id.toString()) {
      throw forbidden('You can only call your own clinic thread');
    }

    const room = `clinq-care-${patientId}`;

    // A patient rings the clinic (its doctors); a clinician rings that patient.
    let toUserIds;
    if (isPatient) {
      const doctors = await User.find({ role: ROLES.DOCTOR, isActive: true }).select('_id').lean();
      toUserIds = doctors.map((d) => d._id);
    } else {
      toUserIds = [patientId];
    }

    const result = await notifyIncomingCall({
      toUserIds,
      callerName: req.user.name,
      room,
      video: req.body.video,
    });

    res.json({ room, delivered: result.delivered });
  }),
);

export default router;

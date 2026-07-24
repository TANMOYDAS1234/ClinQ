import { Router } from 'express';
import dayjs from 'dayjs';
import crypto from 'node:crypto';
import { z } from 'zod';
import { requireAuth, requireClinician } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound, badRequest, forbidden } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { Appointment, APPOINTMENT_STATUS } from '../models/Appointment.js';
import { User, ROLES } from '../models/User.js';
import { paged, pageParams, dateRange } from '../utils/pagination.js';

const router = Router();
router.use(requireAuth);

/** Clinic hours. In a multi-doctor build this moves to a schedule collection. */
const CLINIC = { openHour: 10, closeHour: 19, slotMinutes: 15, breakStart: 14, breakEnd: 16 };

const isPatient = (req) => req.user.role === ROLES.PATIENT;

/** Patients see only their own appointments; clinicians see the whole diary. */
function scopeFilter(req) {
  return isPatient(req) ? { patient: req.user._id } : {};
}

router.get(
  '/',
  validate({
    query: pageParams.and(
      z.object({
        status: z.enum(APPOINTMENT_STATUS).optional(),
        patientId: z.string().optional(),
      }),
    ),
  }),
  audit('read', 'Appointment'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip, from, to, status, patientId } = q(req);

    const filter = {
      ...scopeFilter(req),
      ...dateRange('scheduledFor', { from, to }),
      ...(status ? { status } : {}),
      ...(!isPatient(req) && patientId ? { patient: patientId } : {}),
    };

    const [items, total] = await Promise.all([
      Appointment.find(filter)
        .sort({ scheduledFor: -1 })
        .skip(skip)
        .limit(limit)
        .populate('patient', 'name phone')
        .populate('doctor', 'name')
        .lean(),
      Appointment.countDocuments(filter),
    ]);

    res.json(paged(items.map(serialise), { page, limit, total }));
  }),
);

router.post(
  '/',
  validate({
    body: z.object({
      scheduledFor: z.coerce.date(),
      mode: z.enum(['in_clinic', 'teleconsult']).default('in_clinic'),
      reason: z.string().max(600).optional(),
      patientId: z.string().optional(),
      doctorId: z.string().optional(),
    }),
  }),
  audit('create', 'Appointment'),
  asyncHandler(async (req, res) => {
    const { scheduledFor, mode, reason } = req.body;

    if (dayjs(scheduledFor).isBefore(dayjs())) {
      throw badRequest('Appointment time must be in the future');
    }

    const patientId = isPatient(req) ? req.user._id : req.body.patientId;
    if (!patientId) throw badRequest('patientId is required');

    const doctor = req.body.doctorId
      ? await User.findOne({ _id: req.body.doctorId, role: ROLES.DOCTOR })
      : await User.findOne({ role: ROLES.DOCTOR });
    if (!doctor) throw badRequest('No doctor is available for booking');

    // Reject a double-booking of the same slot.
    const slotStart = dayjs(scheduledFor);
    const clash = await Appointment.findOne({
      doctor: doctor._id,
      status: { $in: ['requested', 'confirmed', 'checked_in', 'in_consultation'] },
      scheduledFor: {
        $gte: slotStart.toDate(),
        $lt: slotStart.add(CLINIC.slotMinutes, 'minute').toDate(),
      },
    });
    if (clash) throw badRequest('That time slot has just been taken. Please choose another.');

    const appointment = await Appointment.create({
      patient: patientId,
      doctor: doctor._id,
      scheduledFor,
      mode,
      reason,
      durationMinutes: CLINIC.slotMinutes,
      status: isPatient(req) ? 'requested' : 'confirmed',
      ...(mode === 'teleconsult'
        ? { teleconsult: { roomId: crypto.randomUUID(), joinUrl: null } }
        : {}),
    });

    res.status(201).json({ appointment: serialise(await appointment.populate('patient doctor', 'name phone')) });
  }),
);

router.patch(
  '/:id/reschedule',
  validate({ body: z.object({ scheduledFor: z.coerce.date() }) }),
  audit('update', 'Appointment'),
  asyncHandler(async (req, res) => {
    const existing = await Appointment.findOne({ _id: req.params.id, ...scopeFilter(req) });
    if (!existing) throw notFound('Appointment not found');
    if (['completed', 'cancelled'].includes(existing.status)) {
      throw badRequest('This appointment can no longer be changed');
    }
    if (dayjs(req.body.scheduledFor).isBefore(dayjs())) {
      throw badRequest('Appointment time must be in the future');
    }

    // Preserve the original as an audit trail rather than mutating in place.
    existing.status = 'cancelled';
    existing.cancellationReason = 'Rescheduled by patient';
    existing.cancelledBy = req.user._id;
    await existing.save();

    const replacement = await Appointment.create({
      patient: existing.patient,
      doctor: existing.doctor,
      scheduledFor: req.body.scheduledFor,
      mode: existing.mode,
      reason: existing.reason,
      durationMinutes: existing.durationMinutes,
      status: 'requested',
      rescheduledFrom: existing._id,
    });

    res.json({ appointment: serialise(await replacement.populate('patient doctor', 'name phone')) });
  }),
);

router.patch(
  '/:id/cancel',
  validate({ body: z.object({ reason: z.string().max(500).optional() }) }),
  audit('update', 'Appointment'),
  asyncHandler(async (req, res) => {
    const appt = await Appointment.findOne({ _id: req.params.id, ...scopeFilter(req) });
    if (!appt) throw notFound('Appointment not found');
    if (appt.status === 'completed') throw badRequest('Completed appointments cannot be cancelled');

    appt.status = 'cancelled';
    appt.cancelledBy = req.user._id;
    appt.cancellationReason = req.body.reason;
    await appt.save();

    res.json({ appointment: serialise(appt) });
  }),
);

router.patch(
  '/:id/status',
  requireClinician,
  validate({ body: z.object({ status: z.enum(APPOINTMENT_STATUS), consultationNotes: z.string().max(8000).optional() }) }),
  audit('update', 'Appointment'),
  asyncHandler(async (req, res) => {
    const appt = await Appointment.findByIdAndUpdate(
      req.params.id,
      { $set: req.body, ...(req.body.status === 'in_consultation' ? { calledAt: new Date() } : {}) },
      { new: true },
    );
    if (!appt) throw notFound('Appointment not found');
    res.json({ appointment: serialise(appt) });
  }),
);

/** Bookable slots for a day, with taken ones marked unavailable. */
router.get(
  '/slots',
  validate({ query: z.object({ date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/), doctorId: z.string().optional() }) }),
  asyncHandler(async (req, res) => {
    const day = dayjs(q(req).date);
    if (!day.isValid()) throw badRequest('Invalid date');

    const doctor = q(req).doctorId
      ? await User.findById(q(req).doctorId)
      : await User.findOne({ role: ROLES.DOCTOR });
    if (!doctor) throw badRequest('No doctor is available');

    const booked = await Appointment.find({
      doctor: doctor._id,
      status: { $in: ['requested', 'confirmed', 'checked_in', 'in_consultation'] },
      scheduledFor: { $gte: day.startOf('day').toDate(), $lte: day.endOf('day').toDate() },
    })
      .select('scheduledFor')
      .lean();

    const takenTimes = new Set(booked.map((b) => dayjs(b.scheduledFor).format('HH:mm')));
    const now = dayjs();
    const slots = [];

    for (let h = CLINIC.openHour; h < CLINIC.closeHour; h += 1) {
      if (h >= CLINIC.breakStart && h < CLINIC.breakEnd) continue;
      for (let m = 0; m < 60; m += CLINIC.slotMinutes) {
        const slot = day.hour(h).minute(m).second(0);
        const time = slot.format('HH:mm');
        slots.push({
          time,
          available: !takenTimes.has(time) && slot.isAfter(now),
        });
      }
    }

    res.json({ date: day.format('YYYY-MM-DD'), doctorId: doctor._id, slots });
  }),
);

/** Live queue for the clinic waiting room. */
router.get(
  '/queue/today',
  asyncHandler(async (req, res) => {
    const today = dayjs().format('YYYY-MM-DD');

    const entries = await Appointment.find({
      queueDate: today,
      status: { $in: ['checked_in', 'in_consultation'] },
    })
      .sort({ isPriority: -1, queueNumber: 1 })
      .populate('patient', 'name')
      .lean();

    const nowServing = entries.find((e) => e.status === 'in_consultation');

    res.json({
      date: today,
      nowServing: nowServing?.queueNumber ?? null,
      entries: entries.map((e) => ({
        queueNumber: e.queueNumber,
        // Patients see only their own name in the queue; others are masked.
        patientName:
          isPatient(req) && e.patient?._id?.toString() !== req.user._id.toString()
            ? 'Patient'
            : (e.patient?.name ?? 'Patient'),
        status: e.status,
        isPriority: e.isPriority,
        isYou: e.patient?._id?.toString() === req.user._id.toString(),
      })),
    });
  }),
);

router.post(
  '/:id/check-in',
  audit('update', 'Appointment'),
  asyncHandler(async (req, res) => {
    const appt = await Appointment.findOne({ _id: req.params.id, ...scopeFilter(req) });
    if (!appt) throw notFound('Appointment not found');
    if (appt.status === 'checked_in') {
      return res.json({ queueNumber: appt.queueNumber, position: null, estimatedWaitMinutes: null });
    }
    if (!['requested', 'confirmed'].includes(appt.status)) {
      throw badRequest('This appointment cannot be checked in');
    }

    const today = dayjs().format('YYYY-MM-DD');
    const last = await Appointment.findOne({ queueDate: today }).sort({ queueNumber: -1 }).select('queueNumber').lean();

    appt.queueDate = today;
    appt.queueNumber = (last?.queueNumber ?? 0) + 1;
    appt.status = 'checked_in';
    await appt.save();

    const ahead = await Appointment.countDocuments({
      queueDate: today,
      status: { $in: ['checked_in', 'in_consultation'] },
      queueNumber: { $lt: appt.queueNumber },
    });

    res.json({
      queueNumber: appt.queueNumber,
      position: ahead + 1,
      estimatedWaitMinutes: ahead * CLINIC.slotMinutes,
    });
  }),
);

function serialise(a) {
  const patient = a.patient && typeof a.patient === 'object' && a.patient.name ? a.patient : null;
  const doctor = a.doctor && typeof a.doctor === 'object' && a.doctor.name ? a.doctor : null;
  return {
    id: a._id,
    patientId: patient?._id ?? a.patient,
    patientName: patient?.name ?? null,
    doctorId: doctor?._id ?? a.doctor,
    doctorName: doctor?.name ?? null,
    scheduledFor: a.scheduledFor,
    durationMinutes: a.durationMinutes,
    mode: a.mode,
    status: a.status,
    reason: a.reason ?? null,
    queueNumber: a.queueNumber ?? null,
    isPriority: a.isPriority ?? false,
    teleconsult: a.teleconsult?.roomId
      ? { roomId: a.teleconsult.roomId, joinUrl: a.teleconsult.joinUrl ?? null }
      : null,
    consultationNotes: a.consultationNotes ?? null,
    createdAt: a.createdAt,
  };
}

export default router;

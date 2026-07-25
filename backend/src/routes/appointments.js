import { Router } from 'express';
import dayjs from 'dayjs';
import crypto from 'node:crypto';
import { z } from 'zod';
import { requireAuth, requireClinician } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound, badRequest } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { Appointment, APPOINTMENT_STATUS } from '../models/Appointment.js';
import { Clinic } from '../models/Clinic.js';
import { User, ROLES } from '../models/User.js';
import { ACTIVE_STATUSES, isSlotBookable } from '../services/scheduling.js';
import { paged, pageParams, dateRange } from '../utils/pagination.js';

const router = Router();
router.use(requireAuth);

/** Fallback slot length for teleconsults and queue estimates (no clinic). */
const DEFAULT_SLOT_MINUTES = 15;

const isPatient = (req) => req.user.role === ROLES.PATIENT;

/** Patients see only their own appointments; clinicians see the whole diary. */
function scopeFilter(req) {
  return isPatient(req) ? { patient: req.user._id } : {};
}

const POPULATE = [
  { path: 'patient', select: 'name phone' },
  { path: 'doctor', select: 'name' },
  { path: 'clinic', select: 'name addressLine city phone' },
];

router.get(
  '/',
  validate({
    query: pageParams.and(
      z.object({
        status: z.enum(APPOINTMENT_STATUS).optional(),
        patientId: z.string().optional(),
        clinicId: z.string().optional(),
      }),
    ),
  }),
  audit('read', 'Appointment'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip, from, to, status, patientId, clinicId } = q(req);

    const filter = {
      ...scopeFilter(req),
      ...dateRange('scheduledFor', { from, to }),
      ...(status ? { status } : {}),
      ...(clinicId ? { clinic: clinicId } : {}),
      ...(!isPatient(req) && patientId ? { patient: patientId } : {}),
    };

    const [items, total] = await Promise.all([
      Appointment.find(filter)
        .sort({ scheduledFor: -1 })
        .skip(skip)
        .limit(limit)
        .populate(POPULATE)
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
      clinicId: z.string().optional(),
      mode: z.enum(['in_clinic', 'teleconsult']).default('in_clinic'),
      reason: z.string().max(600).optional(),
      patientId: z.string().optional(),
      doctorId: z.string().optional(),
    }),
  }),
  audit('create', 'Appointment'),
  asyncHandler(async (req, res) => {
    const { scheduledFor, mode, reason, clinicId } = req.body;

    if (dayjs(scheduledFor).isBefore(dayjs())) {
      throw badRequest('Appointment time must be in the future');
    }

    const patientId = isPatient(req) ? req.user._id : req.body.patientId;
    if (!patientId) throw badRequest('patientId is required');

    const doctor = req.body.doctorId
      ? await User.findOne({ _id: req.body.doctorId, role: ROLES.DOCTOR })
      : await User.findOne({ role: ROLES.DOCTOR });
    if (!doctor) throw badRequest('No doctor is available for booking');

    // An in-clinic visit must land on a real, free slot of the chosen clinic's
    // schedule. This is the authoritative check — the client cannot book a time
    // the schedule does not offer, or one already taken.
    let clinic = null;
    if (mode === 'in_clinic') {
      if (!clinicId) throw badRequest('Please choose a clinic');
      clinic = await Clinic.findOne({ _id: clinicId, isActive: true });
      if (!clinic) throw badRequest('That clinic is not available');
      if (!(await isSlotBookable(clinic, scheduledFor))) {
        throw badRequest('That time slot is no longer available. Please choose another.');
      }
    }

    // Second guard against a race — two patients validating the same free slot
    // in the same instant. The unique-ish window catches the loser.
    const slotStart = dayjs(scheduledFor);
    const clash = await Appointment.findOne({
      ...(clinic ? { clinic: clinic._id } : { doctor: doctor._id, clinic: null }),
      status: { $in: ACTIVE_STATUSES },
      scheduledFor: {
        $gte: slotStart.toDate(),
        $lt: slotStart.add(clinic?.slotMinutes ?? DEFAULT_SLOT_MINUTES, 'minute').toDate(),
      },
    });
    if (clash) throw badRequest('That time slot has just been taken. Please choose another.');

    const appointment = await Appointment.create({
      patient: patientId,
      doctor: doctor._id,
      clinic: clinic?._id,
      scheduledFor,
      mode,
      reason,
      durationMinutes: clinic?.slotMinutes ?? DEFAULT_SLOT_MINUTES,
      // Auto-confirm: booking a free slot grants it immediately — no manual
      // approval step. The clinic can still cancel or reschedule afterwards.
      status: 'confirmed',
      ...(mode === 'teleconsult'
        ? { teleconsult: { roomId: crypto.randomUUID(), joinUrl: null } }
        : {}),
    });

    await appointment.populate(POPULATE);
    res.status(201).json({ appointment: serialise(appointment) });
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

    // Re-validate the new time against the same clinic's live schedule.
    if (existing.clinic) {
      const clinic = await Clinic.findOne({ _id: existing.clinic, isActive: true });
      if (!clinic) throw badRequest('That clinic is not available');
      if (!(await isSlotBookable(clinic, req.body.scheduledFor))) {
        throw badRequest('That time slot is not available. Please choose another.');
      }
    }

    // Preserve the original as an audit trail rather than mutating in place.
    existing.status = 'cancelled';
    existing.cancellationReason = 'Rescheduled by patient';
    existing.cancelledBy = req.user._id;
    await existing.save();

    const replacement = await Appointment.create({
      patient: existing.patient,
      doctor: existing.doctor,
      clinic: existing.clinic,
      scheduledFor: req.body.scheduledFor,
      mode: existing.mode,
      reason: existing.reason,
      durationMinutes: existing.durationMinutes,
      status: 'requested',
      rescheduledFrom: existing._id,
    });

    await replacement.populate(POPULATE);
    res.json({ appointment: serialise(replacement) });
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

    await appt.populate(POPULATE);
    res.json({ appointment: serialise(appt) });
  }),
);

router.patch(
  '/:id/status',
  requireClinician,
  validate({
    body: z.object({
      status: z.enum(APPOINTMENT_STATUS),
      consultationNotes: z.string().max(8000).optional(),
    }),
  }),
  audit('update', 'Appointment'),
  asyncHandler(async (req, res) => {
    const appt = await Appointment.findByIdAndUpdate(
      req.params.id,
      { $set: req.body, ...(req.body.status === 'in_consultation' ? { calledAt: new Date() } : {}) },
      { new: true },
    ).populate(POPULATE);
    if (!appt) throw notFound('Appointment not found');
    res.json({ appointment: serialise(appt) });
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
      estimatedWaitMinutes: ahead * (appt.durationMinutes ?? DEFAULT_SLOT_MINUTES),
    });
  }),
);

function serialise(a) {
  const patient = a.patient && typeof a.patient === 'object' && a.patient.name ? a.patient : null;
  const doctor = a.doctor && typeof a.doctor === 'object' && a.doctor.name ? a.doctor : null;
  const clinic = a.clinic && typeof a.clinic === 'object' && a.clinic.name ? a.clinic : null;
  return {
    id: a._id,
    patientId: patient?._id ?? a.patient,
    patientName: patient?.name ?? null,
    patientPhone: patient?.phone ?? null,
    doctorId: doctor?._id ?? a.doctor,
    doctorName: doctor?.name ?? null,
    clinicId: clinic?._id ?? a.clinic ?? null,
    clinic: clinic
      ? {
          id: clinic._id,
          name: clinic.name,
          addressLine: clinic.addressLine ?? null,
          city: clinic.city ?? null,
          phone: clinic.phone ?? null,
        }
      : null,
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

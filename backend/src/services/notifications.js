import { User, ROLES } from '../models/User.js';
import { ClinicalAlert } from '../models/ClinicalAlert.js';
import { logger } from '../config/logger.js';

/**
 * Notification transport.
 *
 * Delivery is stubbed at the transport boundary: alerts and their
 * notified-at timestamps are persisted for real, but the actual push is
 * logged rather than sent. Swap `deliver()` for FCM/APNs (or an SMS gateway
 * for the emergency path) without touching any caller.
 */
async function deliver({ tokens, title, body, data }) {
  if (!tokens?.length) {
    logger.debug({ title }, 'no device tokens registered; notification skipped');
    return { delivered: 0 };
  }
  logger.info({ title, body, tokenCount: tokens.length, data }, '[push] would deliver');
  return { delivered: tokens.length };
}

export async function notifyClinicStaff(alert) {
  const staff = await User.find({ role: { $in: [ROLES.DOCTOR, ROLES.STAFF] }, isActive: true })
    .select('deviceTokens name')
    .lean();

  const tokens = staff.flatMap((s) => s.deviceTokens ?? []);
  await deliver({
    tokens,
    title: `${alert.severity === 'emergency' ? '🚨 EMERGENCY' : '⚠️ Urgent'}: ${alert.title}`,
    body: alert.detail?.slice(0, 180) ?? '',
    data: { alertId: alert._id.toString(), patientId: alert.patient.toString(), type: alert.type },
  });

  await ClinicalAlert.findByIdAndUpdate(alert._id, { notifiedStaffAt: new Date() });
}

export async function notifyPatient(patientId, alert) {
  const patient = await User.findById(patientId).select('deviceTokens language').lean();
  if (!patient) return;

  await deliver({
    tokens: patient.deviceTokens ?? [],
    title: 'Please seek medical attention',
    body: alert.title,
    data: { alertId: alert._id.toString(), type: alert.type },
  });

  await ClinicalAlert.findByIdAndUpdate(alert._id, { notifiedPatientAt: new Date() });
}

/** The clinic has replied inside the patient's assistant thread. */
export async function notifyPatientOfClinicianReply(patientId, clinician, content) {
  const patient = await User.findById(patientId).select('deviceTokens').lean();
  await deliver({
    tokens: patient?.deviceTokens ?? [],
    title: `${clinician.name} replied`,
    body: content.slice(0, 180),
    // `kind` lets the app route the tap straight to the conversation.
    data: { kind: 'clinician_reply', patientId: patientId.toString() },
  });
}

/**
 * A patient has booked, moved or cancelled an appointment.
 *
 * Sent the moment it happens rather than batched: a cancellation an hour from
 * now is only useful if the doctor hears about it in time to refill the slot.
 */
export async function notifyClinicOfAppointmentChange(appointment, patientName, change) {
  const staff = await User.find({ role: { $in: [ROLES.DOCTOR, ROLES.STAFF] }, isActive: true })
    .select('deviceTokens')
    .lean();

  const when = new Date(appointment.scheduledFor).toLocaleString('en-IN', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Kolkata',
  });

  const verb = { booked: 'booked', rescheduled: 'moved', cancelled: 'cancelled' }[change] ?? change;

  await deliver({
    tokens: staff.flatMap((s) => s.deviceTokens ?? []),
    title: `Appointment ${verb}`,
    body: `${patientName} — ${when}`,
    data: {
      kind: 'appointment_change',
      change,
      appointmentId: appointment._id.toString(),
      patientId: appointment.patient.toString(),
    },
  });
}

/**
 * Tell the patient their appointment was cancelled, rejected or moved.
 *
 * The one notification a patient cannot afford to miss after an emergency
 * alert: without it they travel to the clinic for an appointment that is no
 * longer there. Reaches them whether the clinic or they themselves made the
 * change, because a reschedule confirmed on someone else's screen is not a
 * reschedule they know about.
 */
export async function notifyPatientOfAppointmentChange(appointment, change, reason) {
  const patientId = appointment.patient?._id ?? appointment.patient;
  const patient = await User.findById(patientId).select('deviceTokens').lean();
  if (!patient) return;

  const when = new Date(appointment.scheduledFor).toLocaleString('en-IN', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Kolkata',
  });

  const title = {
    cancelled: 'Your appointment was cancelled',
    rejected: 'Your appointment could not be confirmed',
    rescheduled: 'Your appointment was moved',
  }[change] ?? 'Your appointment changed';

  await deliver({
    tokens: patient.deviceTokens ?? [],
    title,
    // The reason matters: "the doctor is unavailable" and "please come at a
    // different time" call for different things from the patient.
    body: reason ? `${when} — ${reason}` : `${when}. Please book another time.`,
    data: {
      kind: 'appointment_change_patient',
      change,
      appointmentId: appointment._id.toString(),
    },
  });
}

/**
 * Evening summary of the next day's list, for the doctor.
 *
 * Deliberately the evening before rather than the morning of: the point of
 * knowing the day's shape is to be able to act on it — move a clash, prepare
 * for a complex case, start late if the morning is empty — and by the time the
 * clinic opens, none of that is possible any more. Same-day changes are covered
 * by [notifyClinicOfAppointmentChange], which fires immediately.
 *
 * Caller supplies the appointments so this stays a pure transport function and
 * the scheduling query lives with the rest of the scheduling logic.
 */
export async function notifyClinicOfTomorrowSchedule(appointments) {
  const doctors = await User.find({ role: ROLES.DOCTOR, isActive: true }).select('deviceTokens').lean();
  const tokens = doctors.flatMap((d) => d.deviceTokens ?? []);

  if (!appointments.length) {
    await deliver({
      tokens,
      title: 'Tomorrow: no appointments',
      body: 'Your schedule is clear.',
      data: { kind: 'schedule_digest', count: '0' },
    });
    return;
  }

  const first = new Date(appointments[0].scheduledFor).toLocaleTimeString('en-IN', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: 'Asia/Kolkata',
  });

  await deliver({
    tokens,
    title: `Tomorrow: ${appointments.length} appointment${appointments.length === 1 ? '' : 's'}`,
    body: `First at ${first}.`,
    data: { kind: 'schedule_digest', count: String(appointments.length) },
  });
}

/**
 * Tell waitlisted patients that a slot has opened on a day they wanted.
 *
 * Only patients who explicitly joined the waitlist are contacted — see
 * [AppointmentWaitlist] for why this is never a broadcast.
 *
 * Entries are notified highest clinical risk first. The slot still goes to
 * whoever books it, but the patient whose control is worst gets the head start,
 * which is the only ordering a clinic could defend.
 */
export async function notifyWaitlistOfFreedSlot(entries, appointment) {
  if (!entries.length) return { notified: 0 };

  const when = new Date(appointment.scheduledFor).toLocaleString('en-IN', {
    dateStyle: 'medium',
    timeStyle: 'short',
    timeZone: 'Asia/Kolkata',
  });

  const patients = await User.find({ _id: { $in: entries.map((e) => e.patient) } })
    .select('deviceTokens')
    .lean();

  const byId = new Map(patients.map((p) => [p._id.toString(), p]));

  for (const entry of entries) {
    const patient = byId.get(entry.patient.toString());
    await deliver({
      tokens: patient?.deviceTokens ?? [],
      title: 'An appointment has opened up',
      body: `${when} is now free. Book it before someone else does.`,
      data: {
        kind: 'slot_freed',
        appointmentAt: new Date(appointment.scheduledFor).toISOString(),
        clinicId: appointment.clinic?.toString() ?? '',
      },
    });
  }

  return { notified: entries.length };
}

export async function notifyMedicationReminder(patientId, medication) {
  const patient = await User.findById(patientId).select('deviceTokens').lean();
  await deliver({
    tokens: patient?.deviceTokens ?? [],
    title: 'Medication reminder',
    body: `Time to take ${medication.name}`,
    data: { medicationId: medication._id.toString(), kind: 'medication_reminder' },
  });
}

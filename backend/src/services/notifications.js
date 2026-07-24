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

export async function notifyMedicationReminder(patientId, medication) {
  const patient = await User.findById(patientId).select('deviceTokens').lean();
  await deliver({
    tokens: patient?.deviceTokens ?? [],
    title: 'Medication reminder',
    body: `Time to take ${medication.name}`,
    data: { medicationId: medication._id.toString(), kind: 'medication_reminder' },
  });
}

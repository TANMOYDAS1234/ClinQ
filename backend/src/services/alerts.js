import { ClinicalAlert } from '../models/ClinicalAlert.js';
import { logger } from '../config/logger.js';
import { notifyClinicStaff, notifyPatient } from './notifications.js';

/**
 * Creates an escalation record and pushes it to whoever needs to see it.
 *
 * De-duplicates: an identical open alert for the same patient within the
 * dedupe window is reused rather than creating a second one, so a patient
 * sending three panicked messages does not produce three identical pages.
 */
export async function raiseAlert({
  patientId,
  severity,
  type,
  title,
  detail,
  source,
  matchedRules = [],
  dedupeWindowMinutes = 30,
}) {
  const since = new Date(Date.now() - dedupeWindowMinutes * 60 * 1000);

  const existing = await ClinicalAlert.findOne({
    patient: patientId,
    type,
    status: 'open',
    createdAt: { $gte: since },
  });

  if (existing) {
    logger.debug({ alertId: existing._id, type }, 'reusing recent open alert');
    return existing;
  }

  const alert = await ClinicalAlert.create({
    patient: patientId,
    severity,
    type,
    title,
    detail,
    source,
    matchedRules,
  });

  logger.warn({ alertId: alert._id.toString(), patientId: String(patientId), type, severity }, 'clinical alert raised');

  // Notification failures must not roll back the alert — the record in the
  // doctor dashboard is the durable part; push is best-effort.
  if (severity === 'emergency' || severity === 'urgent') {
    notifyClinicStaff(alert).catch((err) => logger.error({ err }, 'staff notification failed'));
  }
  if (severity === 'emergency') {
    notifyPatient(patientId, alert).catch((err) => logger.error({ err }, 'patient notification failed'));
  }

  return alert;
}

export async function acknowledgeAlert(alertId, userId) {
  return ClinicalAlert.findByIdAndUpdate(
    alertId,
    { status: 'acknowledged', acknowledgedBy: userId, acknowledgedAt: new Date() },
    { new: true },
  );
}

export async function resolveAlert(alertId, userId, notes) {
  return ClinicalAlert.findByIdAndUpdate(
    alertId,
    { status: 'resolved', resolvedBy: userId, resolvedAt: new Date(), resolutionNotes: notes },
    { new: true },
  );
}

import dayjs from 'dayjs';
import { PatientProfile } from '../models/PatientProfile.js';
import { GlucoseReading } from '../models/GlucoseReading.js';
import { Medication } from '../models/Medication.js';
import { VitalRecord } from '../models/VitalRecord.js';
import { Hba1cRecord } from '../models/Hba1cRecord.js';
import { Appointment } from '../models/Appointment.js';

/**
 * Builds the compact clinical picture injected into the assistant prompt.
 *
 * Deliberately terse: this is prepended to every chat turn, so it is a summary
 * rather than a dump. Only what changes an answer belongs here — an assistant
 * that knows the patient is on insulin and ran 320 mg/dL this morning gives a
 * materially different reply than one that does not.
 */
export async function buildPatientContext(patientId) {
  const [profile, recentGlucose, meds, latestVital, latestHba1c, nextAppt] = await Promise.all([
    PatientProfile.findOne({ user: patientId }).lean(),
    GlucoseReading.find({ patient: patientId })
      .sort({ measuredAt: -1 })
      .limit(10)
      .select('valueMgDl context measuredAt flag')
      .lean(),
    Medication.find({ patient: patientId, isActive: true }).select('name strength dose form schedule').lean(),
    VitalRecord.findOne({ patient: patientId }).sort({ recordedAt: -1 }).lean(),
    Hba1cRecord.findOne({ patient: patientId }).sort({ testedOn: -1 }).lean(),
    Appointment.findOne({
      patient: patientId,
      status: { $in: ['requested', 'confirmed'] },
      scheduledFor: { $gte: new Date() },
    })
      .sort({ scheduledFor: 1 })
      .lean(),
  ]);

  const lines = [];

  if (profile) {
    const bits = [];
    if (profile.diabetesType && profile.diabetesType !== 'none') {
      bits.push(`Diabetes: ${profile.diabetesType.replace('type', 'Type ')}`);
    }
    if (profile.diagnosedOn) bits.push(`diagnosed ${dayjs(profile.diagnosedOn).format('MMM YYYY')}`);
    if (bits.length) lines.push(`- ${bits.join(', ')}`);

    if (profile.comorbidities?.length) {
      lines.push(`- Other conditions: ${profile.comorbidities.join(', ')}`);
    }
    if (profile.allergies?.length) {
      lines.push(`- Known allergies: ${profile.allergies.join(', ')}`);
    }
    if (profile.targets) {
      lines.push(
        `- Targets: fasting ${profile.targets.fastingMin}-${profile.targets.fastingMax} mg/dL, post-meal under ${profile.targets.postPrandialMax} mg/dL, HbA1c under ${profile.targets.hba1cMax}%`,
      );
    }
    if (profile.footRiskCategory && profile.footRiskCategory !== 'low') {
      lines.push(`- Diabetic foot risk category: ${profile.footRiskCategory}`);
    }
  }

  if (recentGlucose?.length) {
    const list = recentGlucose
      .slice(0, 5)
      .map((r) => `${r.valueMgDl} (${r.context.replace('_', ' ')}, ${dayjs(r.measuredAt).fromNow?.() ?? dayjs(r.measuredAt).format('DD MMM HH:mm')})`)
      .join('; ');
    lines.push(`- Recent blood sugar readings, newest first: ${list}`);

    const avg = Math.round(recentGlucose.reduce((s, r) => s + r.valueMgDl, 0) / recentGlucose.length);
    lines.push(`- Average of last ${recentGlucose.length} readings: ${avg} mg/dL`);
  } else {
    lines.push('- No blood sugar readings recorded yet.');
  }

  if (latestHba1c) {
    lines.push(`- Latest HbA1c: ${latestHba1c.percentage}% (${dayjs(latestHba1c.testedOn).format('DD MMM YYYY')})`);
  }

  if (latestVital?.systolic) {
    lines.push(
      `- Latest blood pressure: ${latestVital.systolic}/${latestVital.diastolic} mmHg (${dayjs(latestVital.recordedAt).format('DD MMM')})`,
    );
  }
  if (latestVital?.weightKg) {
    lines.push(`- Latest weight: ${latestVital.weightKg} kg`);
  }

  if (meds?.length) {
    const list = meds
      .map((m) => {
        const times = m.schedule?.map((s) => s.time).join(', ');
        return `${m.name}${m.strength ? ` ${m.strength}` : ''}${m.dose ? ` — ${m.dose}` : ''}${times ? ` at ${times}` : ''}`;
      })
      .join('; ');
    lines.push(`- Current medicines: ${list}`);
  } else {
    lines.push('- No active medicines recorded.');
  }

  if (nextAppt) {
    lines.push(
      `- Next appointment: ${dayjs(nextAppt.scheduledFor).format('DD MMM YYYY, h:mm A')} (${nextAppt.mode.replace('_', ' ')}, ${nextAppt.status})`,
    );
  } else {
    lines.push('- No upcoming appointment booked.');
  }

  return {
    text: lines.join('\n'),
    profile,
    latestGlucose: recentGlucose?.[0] ?? null,
    targets: profile?.targets ?? {},
  };
}

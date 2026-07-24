import dayjs from 'dayjs';
import { GlucoseReading } from '../models/GlucoseReading.js';
import { MedicationLog } from '../models/MedicationLog.js';
import { Medication } from '../models/Medication.js';
import { Hba1cRecord } from '../models/Hba1cRecord.js';
import { VitalRecord } from '../models/VitalRecord.js';
import { LifestyleLog } from '../models/LifestyleLog.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { ClinicalAlert } from '../models/ClinicalAlert.js';
import { GLUCOSE, HBA1C } from './triage/thresholds.js';

/**
 * Health score, 0-100.
 *
 * A weighted composite of the things that actually move diabetes outcomes.
 * Each component is scored independently and only the components with data
 * contribute, so a new patient with one reading is not punished for the
 * metrics they have not recorded yet — `confidence` reports how much of the
 * score is backed by real data.
 *
 * This is an engagement and trend indicator, not a clinical severity index.
 */
const WEIGHTS = Object.freeze({
  timeInRange: 30,
  adherence: 25,
  hba1c: 20,
  bloodPressure: 10,
  activity: 10,
  logging: 5,
});

export async function computeHealthScore(patientId, { days = 30 } = {}) {
  const since = dayjs().subtract(days, 'day').toDate();

  const [readings, profile, hba1c, vitals, activity, adherence] = await Promise.all([
    GlucoseReading.find({ patient: patientId, measuredAt: { $gte: since } })
      .select('valueMgDl context measuredAt flag')
      .lean(),
    PatientProfile.findOne({ user: patientId }).lean(),
    Hba1cRecord.findOne({ patient: patientId }).sort({ testedOn: -1 }).lean(),
    VitalRecord.find({ patient: patientId, recordedAt: { $gte: since } })
      .select('systolic diastolic recordedAt')
      .lean(),
    LifestyleLog.find({ patient: patientId, kind: 'exercise', loggedAt: { $gte: since } })
      .select('durationMinutes loggedAt')
      .lean(),
    computeAdherence(patientId, { days }),
  ]);

  const targets = profile?.targets ?? {};
  const components = {};

  // --- Time in range ---
  if (readings.length >= 3) {
    const inRange = readings.filter(
      (r) => r.valueMgDl >= GLUCOSE.LOW && r.valueMgDl <= (targets.postPrandialMax ?? GLUCOSE.POST_PRANDIAL_TARGET_MAX),
    ).length;
    const pct = (inRange / readings.length) * 100;
    components.timeInRange = { value: Math.round(pct), score: pct / 100, hasData: true };
  } else {
    components.timeInRange = { value: null, score: null, hasData: false };
  }

  // --- Medication adherence ---
  if (adherence.expected > 0) {
    components.adherence = {
      value: adherence.percentage,
      score: adherence.percentage / 100,
      hasData: true,
    };
  } else {
    components.adherence = { value: null, score: null, hasData: false };
  }

  // --- HbA1c (most recent within a year) ---
  if (hba1c && dayjs(hba1c.testedOn).isAfter(dayjs().subtract(1, 'year'))) {
    const target = targets.hba1cMax ?? HBA1C.TARGET_MAX;
    // Full marks at or below target, zero at or above 'poor control'.
    const span = HBA1C.POOR_CONTROL - target;
    const raw = 1 - (hba1c.percentage - target) / span;
    components.hba1c = {
      value: hba1c.percentage,
      score: Math.max(0, Math.min(1, raw)),
      hasData: true,
    };
  } else {
    components.hba1c = { value: null, score: null, hasData: false };
  }

  // --- Blood pressure ---
  if (vitals.length) {
    const withBp = vitals.filter((v) => v.systolic != null);
    if (withBp.length) {
      const atTarget = withBp.filter(
        (v) => v.systolic < (targets.systolicMax ?? 140) && v.diastolic < (targets.diastolicMax ?? 90),
      ).length;
      const pct = (atTarget / withBp.length) * 100;
      components.bloodPressure = { value: Math.round(pct), score: pct / 100, hasData: true };
    } else {
      components.bloodPressure = { value: null, score: null, hasData: false };
    }
  } else {
    components.bloodPressure = { value: null, score: null, hasData: false };
  }

  // --- Activity: WHO minimum is 150 min/week ---
  const weeks = Math.max(1, days / 7);
  const totalMinutes = activity.reduce((s, a) => s + (a.durationMinutes ?? 0), 0);
  const perWeek = totalMinutes / weeks;
  components.activity = {
    value: Math.round(perWeek),
    score: activity.length ? Math.min(1, perWeek / 150) : null,
    hasData: activity.length > 0,
  };

  // --- Logging consistency: distinct days with any glucose entry ---
  const distinctDays = new Set(readings.map((r) => dayjs(r.measuredAt).format('YYYY-MM-DD'))).size;
  const loggingPct = Math.min(1, distinctDays / (days * 0.5)); // logging on half the days = full marks
  components.logging = {
    value: distinctDays,
    score: readings.length ? loggingPct : null,
    hasData: readings.length > 0,
  };

  // Renormalise over components that actually have data.
  let weighted = 0;
  let availableWeight = 0;
  for (const [key, weight] of Object.entries(WEIGHTS)) {
    const c = components[key];
    if (c?.hasData && c.score != null) {
      weighted += c.score * weight;
      availableWeight += weight;
    }
  }

  const score = availableWeight > 0 ? Math.round((weighted / availableWeight) * 100) : null;
  const totalWeight = Object.values(WEIGHTS).reduce((a, b) => a + b, 0);

  return {
    score,
    band: score == null ? 'unknown' : score >= 80 ? 'good' : score >= 60 ? 'fair' : score >= 40 ? 'needs_attention' : 'poor',
    confidence: Math.round((availableWeight / totalWeight) * 100),
    components,
    windowDays: days,
    computedAt: new Date(),
  };
}

/**
 * Medication adherence over a window.
 *
 * Expected doses are derived from each medication's schedule rather than
 * counting only what was logged — otherwise a patient who logs nothing would
 * score 100%.
 */
export async function computeAdherence(patientId, { days = 30 } = {}) {
  const since = dayjs().subtract(days, 'day').startOf('day');
  const now = dayjs();

  const meds = await Medication.find({
    patient: patientId,
    isActive: true,
    startDate: { $lte: now.toDate() },
  })
    .select('schedule daysOfWeek startDate endDate name')
    .lean();

  if (!meds.length) return { expected: 0, taken: 0, missed: 0, percentage: null, perMedication: [] };

  const logs = await MedicationLog.find({
    patient: patientId,
    scheduledFor: { $gte: since.toDate() },
  })
    .select('medication status scheduledFor')
    .lean();

  const logKey = (medId, when) => `${medId}|${dayjs(when).format('YYYY-MM-DDTHH:mm')}`;
  const logMap = new Map(logs.map((l) => [logKey(l.medication, l.scheduledFor), l.status]));

  let expected = 0;
  let taken = 0;
  const perMedication = [];

  for (const med of meds) {
    if (!med.schedule?.length) continue;
    let medExpected = 0;
    let medTaken = 0;

    const start = dayjs.max ? dayjs.max(since, dayjs(med.startDate)) : (dayjs(med.startDate).isAfter(since) ? dayjs(med.startDate) : since);
    const end = med.endDate && dayjs(med.endDate).isBefore(now) ? dayjs(med.endDate) : now;

    for (let d = start.startOf('day'); d.isBefore(end); d = d.add(1, 'day')) {
      if (med.daysOfWeek?.length && !med.daysOfWeek.includes(d.day())) continue;

      for (const slot of med.schedule) {
        const [hh, mm] = slot.time.split(':').map(Number);
        const slotTime = d.hour(hh).minute(mm).second(0).millisecond(0);
        // Only count slots that have already elapsed — a dose due tonight is
        // not yet missed.
        if (slotTime.isAfter(now)) continue;
        if (slotTime.isBefore(since)) continue;

        medExpected += 1;
        if (logMap.get(logKey(med._id, slotTime.toDate())) === 'taken') medTaken += 1;
      }
    }

    expected += medExpected;
    taken += medTaken;
    perMedication.push({
      medicationId: med._id,
      name: med.name,
      expected: medExpected,
      taken: medTaken,
      percentage: medExpected ? Math.round((medTaken / medExpected) * 100) : null,
    });
  }

  return {
    expected,
    taken,
    missed: expected - taken,
    percentage: expected ? Math.round((taken / expected) * 100) : null,
    perMedication,
  };
}

/** Glucose trend series + summary stats for the dashboard chart. */
export async function glucoseTrends(patientId, { days = 30 } = {}) {
  const since = dayjs().subtract(days, 'day').toDate();
  const readings = await GlucoseReading.find({ patient: patientId, measuredAt: { $gte: since } })
    .sort({ measuredAt: 1 })
    .select('valueMgDl context measuredAt flag')
    .lean();

  if (!readings.length) {
    return { days, count: 0, series: [], daily: [], stats: null, distribution: null };
  }

  const values = readings.map((r) => r.valueMgDl);
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const variance = values.reduce((s, v) => s + (v - mean) ** 2, 0) / values.length;

  const byDay = new Map();
  for (const r of readings) {
    const key = dayjs(r.measuredAt).format('YYYY-MM-DD');
    if (!byDay.has(key)) byDay.set(key, []);
    byDay.get(key).push(r.valueMgDl);
  }

  const distribution = {
    severe_low: readings.filter((r) => r.valueMgDl < GLUCOSE.SEVERE_LOW).length,
    low: readings.filter((r) => r.valueMgDl >= GLUCOSE.SEVERE_LOW && r.valueMgDl < GLUCOSE.LOW).length,
    in_range: readings.filter((r) => r.valueMgDl >= GLUCOSE.LOW && r.valueMgDl <= GLUCOSE.POST_PRANDIAL_TARGET_MAX).length,
    high: readings.filter((r) => r.valueMgDl > GLUCOSE.POST_PRANDIAL_TARGET_MAX && r.valueMgDl <= GLUCOSE.HIGH).length,
    very_high: readings.filter((r) => r.valueMgDl > GLUCOSE.HIGH).length,
  };

  return {
    days,
    count: readings.length,
    series: readings.map((r) => ({
      at: r.measuredAt,
      value: r.valueMgDl,
      context: r.context,
      flag: r.flag,
    })),
    daily: [...byDay.entries()].map(([date, vals]) => ({
      date,
      average: Math.round(vals.reduce((a, b) => a + b, 0) / vals.length),
      min: Math.min(...vals),
      max: Math.max(...vals),
      count: vals.length,
    })),
    stats: {
      average: Math.round(mean),
      min: Math.min(...values),
      max: Math.max(...values),
      // Glucose variability; above ~36% is considered unstable control.
      coefficientOfVariation: Math.round((Math.sqrt(variance) / mean) * 100),
      timeInRangePercent: Math.round((distribution.in_range / readings.length) * 100),
      estimatedHba1c: Number(((Math.round(mean) + 46.7) / 28.7).toFixed(1)),
    },
    distribution,
  };
}

/**
 * Recomputes a patient's risk band for doctor-dashboard segmentation.
 * Unlike the health score, this is severity-weighted: recent emergencies and
 * critical readings dominate.
 */
export async function recomputePatientRisk(patientId) {
  const weekAgo = dayjs().subtract(7, 'day').toDate();
  const monthAgo = dayjs().subtract(30, 'day').toDate();

  const [criticalReadings, openEmergencies, openUrgent, adherence, latestHba1c, profile] = await Promise.all([
    GlucoseReading.countDocuments({
      patient: patientId,
      measuredAt: { $gte: weekAgo },
      flag: { $in: ['severe_low', 'critical_high'] },
    }),
    // Emergencies and urgent alerts are weighted separately: an unresolved
    // emergency is not merely "more of" an urgent one. A patient with an open
    // severe-hypoglycaemia alert must surface at the top of the doctor's list
    // even if every other metric looks unremarkable.
    ClinicalAlert.countDocuments({
      patient: patientId,
      status: 'open',
      severity: 'emergency',
      createdAt: { $gte: monthAgo },
    }),
    ClinicalAlert.countDocuments({
      patient: patientId,
      status: 'open',
      severity: 'urgent',
      createdAt: { $gte: monthAgo },
    }),
    computeAdherence(patientId, { days: 30 }),
    Hba1cRecord.findOne({ patient: patientId }).sort({ testedOn: -1 }).lean(),
    PatientProfile.findOne({ user: patientId }),
  ]);

  let risk = 0;
  const reasons = [];

  if (criticalReadings > 0) {
    risk += Math.min(40, criticalReadings * 15);
    reasons.push(`${criticalReadings} critical reading(s) in the last 7 days`);
  }
  if (openEmergencies > 0) {
    // A single unresolved emergency alone clears the 'high' band threshold.
    risk += Math.min(50, 45 + (openEmergencies - 1) * 5);
    reasons.push(`${openEmergencies} unresolved emergency alert(s)`);
  }
  if (openUrgent > 0) {
    risk += Math.min(25, openUrgent * 12);
    reasons.push(`${openUrgent} unresolved urgent alert(s)`);
  }
  if (adherence.percentage != null && adherence.percentage < 70) {
    risk += 20;
    reasons.push(`Medication adherence at ${adherence.percentage}%`);
  }
  if (latestHba1c && latestHba1c.percentage >= HBA1C.POOR_CONTROL) {
    risk += 20;
    reasons.push(`HbA1c ${latestHba1c.percentage}%`);
  }
  if (profile?.footRiskCategory === 'urgent' || profile?.footRiskCategory === 'high') {
    risk += 15;
    reasons.push(`Foot risk category: ${profile.footRiskCategory}`);
  }

  risk = Math.min(100, risk);
  const band = risk >= 70 ? 'critical' : risk >= 45 ? 'high' : risk >= 20 ? 'moderate' : 'low';

  if (profile) {
    profile.riskScore = risk;
    profile.riskBand = band;
    profile.lastRiskComputedAt = new Date();
    await profile.save();
  }

  return { riskScore: risk, riskBand: band, reasons };
}

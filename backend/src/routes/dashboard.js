import { Router } from 'express';
import dayjs from 'dayjs';
import { requireAuth, resolvePatientScope } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { computeHealthScore, computeAdherence, glucoseTrends } from '../services/analytics.js';
import { GlucoseReading } from '../models/GlucoseReading.js';
import { Appointment } from '../models/Appointment.js';
import { ClinicalAlert } from '../models/ClinicalAlert.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { Hba1cRecord } from '../models/Hba1cRecord.js';
import { MedicationLog } from '../models/MedicationLog.js';
import { Medication } from '../models/Medication.js';
import { VitalRecord } from '../models/VitalRecord.js';
import { DietPlan } from '../models/DietPlan.js';
import { FoodLog } from '../models/FoodLog.js';
import { getClinicSettings } from '../models/ClinicSettings.js';

const router = Router({ mergeParams: true });
router.use(requireAuth, resolvePatientScope);

/**
 * One call powers the entire home screen. Everything fans out in parallel —
 * the mobile client on a patchy connection should pay one round trip, not ten.
 */
router.get(
  '/',
  audit('read', 'Dashboard'),
  asyncHandler(async (req, res) => {
    const patientId = req.patientId;

    const [healthScore, trends, adherence, latest, nextAppointment, openAlerts, profile, latestHba1c, todayPending] =
      await Promise.all([
        computeHealthScore(patientId, { days: 30 }),
        glucoseTrends(patientId, { days: 7 }),
        computeAdherence(patientId, { days: 30 }),
        GlucoseReading.findOne({ patient: patientId }).sort({ measuredAt: -1 }).lean(),
        Appointment.findOne({
          patient: patientId,
          status: { $in: ['requested', 'confirmed', 'checked_in'] },
          scheduledFor: { $gte: new Date() },
        })
          .sort({ scheduledFor: 1 })
          .lean(),
        ClinicalAlert.find({ patient: patientId, status: 'open' })
          .sort({ severity: -1, createdAt: -1 })
          .limit(5)
          .lean(),
        PatientProfile.findOne({ user: patientId }).lean(),
        Hba1cRecord.findOne({ patient: patientId }).sort({ testedOn: -1 }).lean(),
        countPendingDosesToday(patientId),
      ]);

    const reminders = {
      footScreeningDue: isDue(profile?.lastFootScreeningAt, profile?.footRiskCategory === 'low' ? 90 : 14),
      eyeScreeningDue: isDue(profile?.lastEyeScreeningAt, 365),
      hba1cDue: isDue(latestHba1c?.testedOn, 90),
    };

    res.json({
      healthScore,
      glucose: {
        latest: latest
          ? { value: latest.valueMgDl, context: latest.context, at: latest.measuredAt, flag: latest.flag }
          : null,
        sevenDayAverage: trends.stats?.average ?? null,
        timeInRangePercent: trends.stats?.timeInRangePercent ?? null,
        sparkline: trends.series.map((s) => ({ at: s.at, value: s.value })),
      },
      adherence: { percentage: adherence.percentage, todayPending },
      nextAppointment: nextAppointment
        ? {
            id: nextAppointment._id,
            scheduledFor: nextAppointment.scheduledFor,
            mode: nextAppointment.mode,
            status: nextAppointment.status,
          }
        : null,
      openAlerts: openAlerts.map((a) => ({
        id: a._id,
        severity: a.severity,
        type: a.type,
        title: a.title,
        createdAt: a.createdAt,
      })),
      recommendations: buildRecommendations({ healthScore, trends, adherence, reminders, latest }),
      reminders,
      ...(await careSummary(patientId, profile, latestHba1c)),
    });
  }),
);

/**
 * The "what my care looks like" half of the home screen: who I am clinically,
 * what I have been told to eat, what I am taking, and what I have logged.
 *
 * Folded into the dashboard call rather than added as a second endpoint — the
 * screen renders as one thing, and a patient on a patchy connection should not
 * watch half of it arrive.
 */
async function careSummary(patientId, profile, latestHba1c) {
  const [latestWeight, plan, medications, foodLogs, settings] = await Promise.all([
    VitalRecord.findOne({ patient: patientId, weightKg: { $ne: null } })
      .sort({ recordedAt: -1 })
      .select('weightKg')
      .lean(),
    // Only a plan the dietician actually sent. A draft they are still editing
    // is not something the patient should be following.
    DietPlan.findOne({ patient: patientId, sharedAt: { $ne: null } })
      .populate('dietician', 'name')
      .lean(),
    Medication.find({ patient: patientId, isActive: true })
      .select('name strength dose schedule instructions')
      .lean(),
    FoodLog.find({ patient: patientId }).sort({ createdAt: -1 }).limit(6).lean(),
    getClinicSettings(),
  ]);

  const weightKg = latestWeight?.weightKg ?? profile?.baselineWeightKg ?? null;
  const heightCm = profile?.heightCm ?? null;
  const bmi =
    weightKg && heightCm ? Number((weightKg / ((heightCm / 100) * (heightCm / 100))).toFixed(1)) : null;

  const hba1cMax = profile?.targets?.hba1cMax ?? 7;

  return {
    profile: {
      diabetesType: profile?.diabetesType ?? null,
      // The clinic's own risk assessment, shown to the patient on their home
      // screen at the clinic's request. Worth noting this is a number the
      // doctor set, not a judgement the app made.
      riskBand: profile?.riskBand ?? null,
      heightCm,
      weightKg,
      bmi,
      allergies: profile?.allergies ?? [],
      reviewIntervalDays: profile?.dietReviewIntervalDays ?? settings.dietReviewIntervalDays,
    },
    latestHba1c: latestHba1c
      ? {
          percentage: latestHba1c.percentage,
          testedOn: latestHba1c.testedOn,
          // Against this patient's own target, not a textbook number — the
          // doctor sets a different ceiling for a frail patient than a young one.
          isHigh: latestHba1c.percentage > hba1cMax,
        }
      : null,
    dietPlan: plan
      ? {
          goal: plan.goal ?? '',
          meals: (plan.meals ?? []).map((m) => ({
            name: m.name,
            time: m.time ?? '',
            items: m.items ?? [],
            notes: m.notes ?? '',
          })),
          avoid: plan.avoid ?? [],
          notes: plan.notes ?? '',
          dieticianName: plan.dietician?.name ?? null,
          sharedAt: plan.sharedAt,
        }
      : null,
    medications: medications.map((m) => ({
      id: String(m._id),
      name: m.name,
      strength: m.strength ?? '',
      dose: m.dose ?? '',
      instructions: m.instructions ?? '',
      times: (m.schedule ?? []).map((s) => s.time).filter(Boolean),
    })),
    recentFoodLogs: foodLogs.map((f) => ({
      id: String(f._id),
      mealType: f.mealType,
      note: f.note ?? '',
      photoUrl: f.photo ? `/api/v1/uploads/${f.photo}/raw` : null,
      createdAt: f.createdAt,
    })),
  };
}

function isDue(lastAt, intervalDays) {
  if (!lastAt) return true;
  return dayjs().diff(dayjs(lastAt), 'day') >= intervalDays;
}

async function countPendingDosesToday(patientId) {
  const day = dayjs();
  const meds = await Medication.find({ patient: patientId, isActive: true }).select('schedule daysOfWeek').lean();
  if (!meds.length) return 0;

  const logs = await MedicationLog.find({
    patient: patientId,
    scheduledFor: { $gte: day.startOf('day').toDate(), $lte: day.endOf('day').toDate() },
    status: { $in: ['taken', 'skipped'] },
  })
    .select('scheduledFor medication')
    .lean();

  const done = new Set(logs.map((l) => `${l.medication}|${dayjs(l.scheduledFor).format('HH:mm')}`));

  let pending = 0;
  for (const med of meds) {
    if (med.daysOfWeek?.length && !med.daysOfWeek.includes(day.day())) continue;
    for (const slot of med.schedule ?? []) {
      if (!done.has(`${med._id}|${slot.time}`)) pending += 1;
    }
  }
  return pending;
}

/**
 * Rule-based, not model-generated. The home screen must render instantly and
 * identically every time — an LLM call here would add latency and variance for
 * no clinical benefit.
 */
function buildRecommendations({ healthScore, trends, adherence, reminders, latest }) {
  const recs = [];

  if (adherence.percentage != null && adherence.percentage < 80) {
    recs.push({
      code: 'IMPROVE_ADHERENCE',
      title: 'Take your medicines on time',
      body: `You have taken ${adherence.percentage}% of your doses this month. Setting reminders can help you stay on track.`,
      priority: adherence.percentage < 60 ? 'high' : 'medium',
    });
  }

  if (trends.stats && trends.stats.timeInRangePercent < 50) {
    recs.push({
      code: 'LOW_TIME_IN_RANGE',
      title: 'Your sugar is often above target',
      body: `Only ${trends.stats.timeInRangePercent}% of your recent readings were in range. Discuss this with Dr. Dey at your next visit.`,
      priority: 'high',
    });
  }

  if (trends.stats && trends.stats.coefficientOfVariation > 36) {
    recs.push({
      code: 'HIGH_VARIABILITY',
      title: 'Your sugar levels are swinging a lot',
      body: 'Large ups and downs can be as important as the average. Try to keep meal times and medicine times consistent.',
      priority: 'medium',
    });
  }

  if (!latest || dayjs().diff(dayjs(latest.measuredAt), 'day') >= 3) {
    recs.push({
      code: 'LOG_MORE',
      title: 'Record a blood sugar reading',
      body: 'It has been a few days since your last reading. Regular readings help Dr. Dey adjust your treatment.',
      priority: 'medium',
    });
  }

  if (reminders.footScreeningDue) {
    recs.push({
      code: 'FOOT_CHECK_DUE',
      title: 'Check your feet',
      body: 'A foot check is due. Take a photo in the Foot Care section so it can be reviewed.',
      priority: 'medium',
    });
  }

  if (reminders.eyeScreeningDue) {
    recs.push({
      code: 'EYE_CHECK_DUE',
      title: 'Annual eye check is due',
      body: 'Diabetic eye problems can be treated early if found early. Book an eye examination.',
      priority: 'medium',
    });
  }

  if (reminders.hba1cDue) {
    recs.push({
      code: 'HBA1C_DUE',
      title: 'HbA1c test is due',
      body: 'This blood test shows your average sugar over the last three months. It is usually done every 3 months.',
      priority: 'medium',
    });
  }

  if (!recs.length && healthScore.score != null && healthScore.score >= 80) {
    recs.push({
      code: 'DOING_WELL',
      title: 'You are doing well',
      body: 'Your readings and medicine routine look good. Keep it up.',
      priority: 'low',
    });
  }

  const order = { high: 0, medium: 1, low: 2 };
  return recs.sort((a, b) => order[a.priority] - order[b.priority]).slice(0, 5);
}

export default router;

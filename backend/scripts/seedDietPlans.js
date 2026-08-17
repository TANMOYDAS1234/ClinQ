/**
 * Writes a starting diet plan for every patient who has none.
 *
 * Built from what the record actually holds — diabetes type, BMI, the latest
 * HbA1c and glucose, blood pressure, kidney function, allergies and the
 * medicines they are on — rather than one template pasted onto everybody. A
 * patient on a sulfonylurea must not skip meals; one on metformin takes it with
 * food; a raised creatinine means protein comes down; a raised BP means salt
 * does. Those are the differences that make a plan worth having.
 *
 * SAFETY, and the reason for every default here:
 *
 *   - Plans are written as DRAFTS. `sharedAt` is left unset, so nothing reaches
 *     a patient and the nutrition assistant will not quote it. A dietician opens
 *     it, reads it, edits it and sends it. Machine-written nutrition advice
 *     going straight to a diabetic patient without a human reading it is not
 *     something this script will do, and --apply does not change that.
 *   - A patient who already has a plan with any content is skipped. This never
 *     overwrites a dietician's work.
 *   - No dietician is credited. The plan carries no author until a real one
 *     saves it, so the patient is never shown advice attributed to a person who
 *     did not write it.
 *   - Nothing is sent, nobody is notified, no review dates move.
 *
 * Reports by default; writes only with --apply.
 *
 *   node scripts/seedDietPlans.js               # who would get one, and what
 *   node scripts/seedDietPlans.js --apply       # write the drafts
 *   node scripts/seedDietPlans.js --apply --patient <id>
 */
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { User, ROLES } from '../src/models/User.js';
import { PatientProfile } from '../src/models/PatientProfile.js';
import { DietPlan } from '../src/models/DietPlan.js';
import { Medication } from '../src/models/Medication.js';
import { Hba1cRecord } from '../src/models/Hba1cRecord.js';
import { GlucoseReading } from '../src/models/GlucoseReading.js';
import { VitalRecord } from '../src/models/VitalRecord.js';
import { LabResult } from '../src/models/LabResult.js';

const apply = process.argv.includes('--apply');
const onlyPatient = (() => {
  const i = process.argv.indexOf('--patient');
  return i !== -1 ? process.argv[i + 1] : null;
})();

// --- Reading the record -----------------------------------------------------

/** Drug classes that change what a meal plan has to say. */
function drugFlags(meds) {
  const names = meds.map((m) => `${m.name} ${m.strength ?? ''}`.toLowerCase()).join(' | ');
  const has = (...needles) => needles.some((n) => names.includes(n));
  return {
    insulin: has('insulin', 'lantus', 'humalog', 'novomix', 'glargine', 'aspart', 'tresiba', 'ryzodeg'),
    // Sulfonylureas drop sugar whether or not the patient ate. Skipping a meal
    // on one of these is how people end up hypoglycaemic.
    sulfonylurea: has('glimepiride', 'gliclazide', 'glipizide', 'glibenclamide', 'amaryl'),
    metformin: has('metformin', 'glycomet', 'gluconorm', 'obimet'),
    // Work on the meal in front of them, so they are taken with the first bite.
    alphaGlucosidase: has('acarbose', 'voglibose', 'miglitol'),
    // Flush glucose through the kidneys; fluid intake matters more on these.
    sglt2: has('dapagliflozin', 'empagliflozin', 'canagliflozin', 'forxiga', 'jardiance'),
    statin: has('atorvastatin', 'rosuvastatin', 'simvastatin'),
  };
}

const numeric = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

/** Everything the plan is written against, in one shape. */
async function readPatient(userId) {
  const [profile, meds, hba1c, glucose, vitals, labs] = await Promise.all([
    PatientProfile.findOne({ user: userId }).lean(),
    Medication.find({ patient: userId, isActive: true }).select('name strength dose schedule').lean(),
    Hba1cRecord.findOne({ patient: userId }).sort({ testedOn: -1 }).lean(),
    GlucoseReading.findOne({ patient: userId }).sort({ measuredAt: -1 }).lean(),
    VitalRecord.find({ patient: userId }).sort({ recordedAt: -1 }).limit(40).lean(),
    LabResult.find({ patient: userId }).sort({ createdAt: -1 }).limit(20).lean(),
  ]);

  const latest = (field) => {
    const rec = vitals.find((v) => v[field] != null);
    return rec ? rec[field] : null;
  };
  const weightKg = latest('weightKg');
  const heightCm = profile?.heightCm ?? null;
  const bmi = weightKg && heightCm ? Number((weightKg / (heightCm / 100) ** 2).toFixed(1)) : null;
  const bp = vitals.find((v) => v.systolic != null);

  // The most recent reading for each analyte the extractor understands.
  const analyte = (key) => {
    for (const l of labs) {
      const v = numeric(l.analysis?.[key]);
      if (v != null) return v;
    }
    return null;
  };

  return {
    profile,
    meds,
    flags: drugFlags(meds),
    bmi,
    weightKg,
    heightCm,
    hba1c: numeric(hba1c?.percentage),
    glucose: numeric(glucose?.valueMgDl),
    systolic: numeric(bp?.systolic),
    creatinine: analyte('creatinine'),
    triglycerides: analyte('triglycerides'),
    ldl: analyte('ldl'),
    allergies: (profile?.allergies ?? []).filter(Boolean),
  };
}

// --- Writing the plan -------------------------------------------------------

/** A daily energy target, rounded to something a person would say out loud. */
function energyTarget({ bmi, weightKg }) {
  if (!weightKg) return null;
  // 20 kcal/kg to reduce, 25 to hold, 30 when underweight — the ordinary
  // starting points, deliberately not dressed up as a precise calculation.
  const perKg = bmi == null ? 25 : bmi >= 25 ? 20 : bmi < 18.5 ? 30 : 25;
  return Math.round((weightKg * perKg) / 50) * 50;
}

function buildGoal(p) {
  const bits = [];
  if (p.hba1c != null && p.hba1c > 7) {
    bits.push(`bring HbA1c down from ${p.hba1c}%`);
  } else if (p.hba1c != null) {
    bits.push(`hold HbA1c at ${p.hba1c}%`);
  } else {
    bits.push('steady blood sugar through the day');
  }
  if (p.bmi != null && p.bmi >= 25) bits.push('lose weight slowly');
  if (p.systolic != null && p.systolic >= 140) bits.push('bring blood pressure down');
  if (p.triglycerides != null && p.triglycerides > 150) bits.push('lower triglycerides');

  const kcal = energyTarget(p);
  const target = kcal ? ` Around ${kcal} kcal a day.` : '';
  return `${bits.join(', ').replace(/^./, (c) => c.toUpperCase())}, without giving up rice or roti.${target}`;
}

/**
 * Meals for the day.
 *
 * Ordinary Indian food, portioned. Nothing here is exotic or expensive: a plan
 * a patient cannot buy in their own market is a plan they will not follow.
 */
function buildMeals(p) {
  const heavy = p.bmi != null && p.bmi >= 25;
  const roti = heavy ? '2 medium roti' : '2–3 medium roti';
  const rice = heavy ? '1 katori rice' : '1–1.5 katori rice';
  const lowSalt = p.systolic != null && p.systolic >= 140;
  const lowProtein = p.creatinine != null && p.creatinine > 1.3;

  const dal = lowProtein ? '1 small katori dal' : '1 katori dal';
  const saltNote = lowSalt ? ' Cook with little salt; no papad, pickle or packet snacks.' : '';

  const meals = [
    {
      name: 'Breakfast',
      time: '8:00 AM',
      items: [
        `${roti === '2 medium roti' ? '2' : '2'} roti or 1 katori upma/poha`,
        '1 katori sabzi or 2 egg whites',
        '1 cup tea or coffee, without sugar',
      ],
      notes:
        (p.flags.metformin ? 'Take metformin with this meal, not before it. ' : '') +
        (p.flags.alphaGlucosidase ? 'Take acarbose/voglibose with the first bite. ' : '') +
        'Eat within an hour of waking.',
    },
    {
      name: 'Mid-morning',
      time: '11:00 AM',
      items: ['1 fruit — guava, apple, papaya or orange', 'or a handful of roasted chana'],
      notes: 'Whole fruit, not juice. Juice raises sugar faster and fills you less.',
    },
    {
      name: 'Lunch',
      time: '1:30 PM',
      items: [
        rice,
        dal,
        '1 katori green sabzi',
        '1 katori curd',
        'Salad — cucumber, tomato, onion — before the rice',
      ],
      notes:
        `Start with the salad, then dal and sabzi, rice last. The same food in that order raises sugar less.${saltNote}`,
    },
    {
      name: 'Evening',
      time: '5:00 PM',
      items: ['1 cup tea without sugar', '1 katori sprouts or 4–5 almonds'],
      notes: p.flags.sulfonylurea
        ? 'Do not skip this one — your tablet lowers sugar whether or not you have eaten.'
        : 'Keeps you from arriving at dinner very hungry.',
    },
    {
      name: 'Dinner',
      time: '8:00 PM',
      items: [roti, '1 katori sabzi', lowProtein ? '1 small katori dal' : '1 katori dal or paneer'],
      notes: `Finish two to three hours before bed. Lighter than lunch.${saltNote}`,
    },
  ];

  if (p.flags.insulin) {
    meals.push({
      name: 'Bedtime',
      time: '10:30 PM',
      items: ['1 cup milk without sugar', 'or 2 marie biscuits'],
      notes: 'Guards against a low overnight. Keep glucose tablets or sugar by the bed.',
    });
  }

  return meals;
}

function buildAvoid(p) {
  const avoid = [
    'Sugar, jaggery and honey in tea or milk',
    'Sweets, cold drinks and packaged fruit juice',
    'Deep-fried snacks — samosa, pakoda, puri',
    'White bread, biscuits and bakery items',
  ];
  if (p.systolic != null && p.systolic >= 140) {
    avoid.push('Pickle, papad, chips and packet namkeen');
  }
  if (p.triglycerides != null && p.triglycerides > 150) {
    avoid.push('Alcohol');
    avoid.push('Vanaspati, dalda and reused frying oil');
  }
  if (p.creatinine != null && p.creatinine > 1.3) {
    avoid.push('Protein powders and supplements unless the doctor asks for them');
  }
  for (const a of p.allergies) avoid.push(`${a} — recorded allergy`);
  return avoid;
}

function buildNotes(p) {
  const lines = [];
  if (p.flags.sulfonylurea) {
    lines.push('Never skip a meal while you are on this tablet — it lowers sugar whether or not you have eaten. Keep sugar or glucose with you.');
  }
  if (p.flags.insulin) {
    lines.push('Eat at roughly the same times each day. Insulin works to a clock, and moving meals about moves your sugars with them.');
  }
  if (p.flags.sglt2) {
    lines.push('Drink water through the day — 8 to 10 glasses — unless the doctor has limited your fluids.');
  }
  if (p.flags.metformin) {
    lines.push('Metformin with food, never on an empty stomach.');
  }
  if (p.bmi != null && p.bmi >= 25) {
    lines.push('Half a kilo a week is the right speed. Faster than that comes back.');
  }
  lines.push('Walk 30 minutes a day, ideally after dinner.');
  lines.push('This is a starting plan. Tell your dietician what you actually eat and it will be adjusted to fit your household.');
  return lines.join('\n');
}

// --- Run --------------------------------------------------------------------

async function main() {
  await mongoose.connect(env.MONGODB_URI);

  const filter = { role: ROLES.PATIENT, isActive: { $ne: false } };
  if (onlyPatient) filter._id = onlyPatient;
  const patients = await User.find(filter).select('name').lean();

  let written = 0;
  let skipped = 0;

  for (const u of patients) {
    const existing = await DietPlan.findOne({ patient: u._id }).lean();
    // Any content at all means somebody has worked on this. Cleared plans left
    // by "start a new plan" are empty, and those are fair to fill.
    const hasContent =
      existing &&
      ((existing.goal ?? '').trim().length > 0 ||
        (existing.meals ?? []).length > 0 ||
        (existing.notes ?? '').trim().length > 0);

    if (hasContent) {
      skipped += 1;
      console.log(`${u.name.padEnd(24)} skipped — already has a plan`);
      continue;
    }

    const p = await readPatient(u._id);
    const plan = {
      goal: buildGoal(p),
      meals: buildMeals(p),
      avoid: buildAvoid(p),
      notes: buildNotes(p),
    };

    const shape = [
      p.bmi != null ? `BMI ${p.bmi}` : null,
      p.hba1c != null ? `HbA1c ${p.hba1c}%` : null,
      p.systolic != null ? `SBP ${p.systolic}` : null,
      p.creatinine != null ? `Cr ${p.creatinine}` : null,
      ...Object.entries(p.flags).filter(([, on]) => on).map(([k]) => k),
    ].filter(Boolean);

    console.log(
      `${u.name.padEnd(24)} ${plan.meals.length} meals, ${plan.avoid.length} to avoid` +
        `${shape.length ? `  [${shape.join(', ')}]` : '  [no clinical data]'}`,
    );

    if (apply) {
      await DietPlan.findOneAndUpdate(
        { patient: u._id },
        {
          patient: u._id,
          ...plan,
          // Deliberately absent: dietician (nobody wrote this yet) and sharedAt
          // (nothing has been given to the patient).
        },
        { upsert: true, new: true, setDefaultsOnInsert: true },
      );
      written += 1;
    }
  }

  console.log(
    `\n${patients.length} patients — ${skipped} already had a plan, ${patients.length - skipped} without one.`,
  );
  if (apply) {
    console.log(`${written} drafts written. None sent: each one shows in the dietician's`);
    console.log("\"Plans to Send\" queue until a dietician reads it and sends it.");
  } else {
    console.log('Nothing written. Re-run with --apply to write the drafts.');
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());

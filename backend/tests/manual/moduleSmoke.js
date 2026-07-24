/**
 * Exercises the clinical modules that are not covered by chatSmoke.js:
 * appointments + queue, foot assessment rules, prescriptions and the
 * medication sync they trigger, lifestyle logging, and vitals escalation.
 *
 *   node tests/manual/moduleSmoke.js
 */
const API = process.env.API ?? 'http://localhost:4000/api/v1';

let passed = 0;
let failed = 0;

function check(label, condition, detail) {
  if (condition) {
    passed += 1;
    console.log(`  PASS  ${label}${detail ? ` — ${detail}` : ''}`);
  } else {
    failed += 1;
    console.log(`  FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
  }
}

async function login(phone, password) {
  const res = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone, password }),
  });
  if (!res.ok) throw new Error(`login ${phone} failed: ${res.status}`);
  return res.json();
}

function client(token) {
  return async (method, path, body) => {
    const res = await fetch(`${API}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      json = { raw: text.slice(0, 200) };
    }
    return { status: res.status, body: json };
  };
}

async function main() {
  const patient = await login('+919830000011', 'Patient@1234');
  const doctor = await login('+919830000001', 'Doctor@1234');
  const p = client(patient.accessToken);
  const d = client(doctor.accessToken);
  const patientId = patient.user.id;

  console.log('\n--- Vitals: hypertensive crisis must escalate ---');
  {
    const r = await p('POST', `/patients/me/vitals`, { systolic: 195, diastolic: 125, pulse: 92 });
    check('crisis BP accepted', r.status === 201, `HTTP ${r.status}`);
    check('flagged hypertensive_crisis', r.body?.record?.flag === 'hypertensive_crisis', r.body?.record?.flag);
    check('emergency alert raised', r.body?.alert?.severity === 'emergency', r.body?.alert?.type);
  }

  console.log('\n--- Vitals: half a BP reading must be rejected ---');
  {
    const r = await p('POST', `/patients/me/vitals`, { systolic: 140 });
    check('rejected with 400', r.status === 400, `HTTP ${r.status}`);
  }

  console.log('\n--- Foot assessment: rules only, no image ---');
  {
    const r = await p('POST', `/patients/me/foot/assessments`, {
      site: 'right_sole',
      symptoms: { pain: 'severe', discharge: true, foulSmell: true, durationDays: 20 },
    });
    check('assessment created', r.status === 201, `HTTP ${r.status}`);
    check('rule risk = urgent', r.body?.assessment?.ruleRiskLevel === 'urgent', r.body?.assessment?.ruleRiskLevel);
    check('final risk = urgent', r.body?.assessment?.finalRiskLevel === 'urgent', r.body?.assessment?.finalRiskLevel);
    check('emergency alert raised', r.body?.alert?.type === 'foot_infection', r.body?.alert?.severity);
    check('follow-up scheduled', Boolean(r.body?.assessment?.followUpDueOn));
  }

  console.log('\n--- Foot assessment: healthy foot stays low risk ---');
  {
    const r = await p('POST', `/patients/me/foot/assessments`, { site: 'left_dorsum', symptoms: {} });
    check('low risk', r.body?.assessment?.finalRiskLevel === 'low', r.body?.assessment?.finalRiskLevel);
    check('no alert', r.body?.alert === null);
  }

  console.log('\n--- Lifestyle logging ---');
  {
    const meal = await p('POST', `/patients/me/lifestyle`, {
      kind: 'meal',
      mealType: 'dinner',
      foodItems: [{ name: 'Roti', quantity: '2', carbsGrams: 30, calories: 160 }],
    });
    check('meal logged', meal.status === 201, `HTTP ${meal.status}`);
    check('carbs totalled', meal.body?.log?.totalCarbsGrams === 30, String(meal.body?.log?.totalCarbsGrams));

    const bad = await p('POST', `/patients/me/lifestyle`, { kind: 'water' });
    check('water without volume rejected', bad.status === 400, `HTTP ${bad.status}`);

    await p('POST', `/patients/me/lifestyle`, { kind: 'water', volumeMl: 500 });
    const summary = await p('GET', `/patients/me/lifestyle/summary`);
    check('daily summary returns water total', summary.body?.water?.totalMl >= 500, `${summary.body?.water?.totalMl} ml`);
  }

  console.log('\n--- Appointments ---');
  {
    const slots = await p('GET', `/appointments/slots?date=${nextWeekday()}`);
    check('slots listed', Array.isArray(slots.body?.slots) && slots.body.slots.length > 0, `${slots.body?.slots?.length} slots`);

    const free = slots.body.slots.find((s) => s.available);
    check('at least one slot free', Boolean(free), free?.time);

    const when = `${nextWeekday()}T${free.time}:00.000Z`;
    const booked = await p('POST', `/appointments`, { scheduledFor: when, mode: 'in_clinic', reason: 'Review' });
    check('appointment booked', booked.status === 201, `HTTP ${booked.status}`);
    check('status is requested', booked.body?.appointment?.status === 'requested');

    const clash = await p('POST', `/appointments`, { scheduledFor: when, mode: 'in_clinic' });
    check('double-booking rejected', clash.status === 400, `HTTP ${clash.status}`);

    const past = await p('POST', `/appointments`, { scheduledFor: '2020-01-01T10:00:00.000Z' });
    check('past date rejected', past.status === 400, `HTTP ${past.status}`);

    const checkedIn = await p('POST', `/appointments/${booked.body.appointment.id}/check-in`);
    check('check-in assigns queue number', typeof checkedIn.body?.queueNumber === 'number', `#${checkedIn.body?.queueNumber}`);

    const queue = await p('GET', `/appointments/queue/today`);
    check('queue lists the patient', queue.body?.entries?.some((e) => e.isYou));

    const cancelled = await p('PATCH', `/appointments/${booked.body.appointment.id}/cancel`, { reason: 'test' });
    check('cancellation works', cancelled.body?.appointment?.status === 'cancelled');
  }

  console.log('\n--- Prescriptions (doctor writes, patient reads) ---');
  {
    const created = await d('POST', `/patients/${patientId}/prescriptions`, {
      diagnosis: ['Type 2 diabetes mellitus', 'Essential hypertension'],
      items: [
        { name: 'Metformin', strength: '1000 mg', dose: '1 tablet', frequency: '1-0-1', durationDays: 30, relationToMeal: 'after_meal' },
        { name: 'Telmisartan', strength: '40 mg', dose: '1 tablet', frequency: 'OD', durationDays: 30 },
      ],
      labTestsAdvised: ['HbA1c', 'Serum creatinine'],
      generalAdvice: 'Continue walking 30 minutes daily.',
    });
    check('prescription created', created.status === 201, `HTTP ${created.status}`);
    check('reference number generated', /^AKD-\d{4}-\d{6}$/.test(created.body?.prescription?.referenceNo ?? ''), created.body?.prescription?.referenceNo);

    const meds = await p('GET', `/patients/me/medications`);
    const synced = meds.body?.items?.find((m) => m.name === 'Metformin');
    check('medication synced from prescription', Boolean(synced));
    check('1-0-1 expanded to two dose times', synced?.schedule?.length === 2, JSON.stringify(synced?.schedule?.map((s) => s.time)));

    const list = await p('GET', `/patients/me/prescriptions`);
    check('patient can read own prescription', list.body?.items?.length > 0, `${list.body?.items?.length} found`);

    const pdf = await fetch(`${API}/patients/me/prescriptions/${created.body.prescription.id}/pdf`, {
      headers: { Authorization: `Bearer ${patient.accessToken}` },
    });
    const html = await pdf.text();
    check('printable view renders', pdf.status === 200 && html.includes('Metformin'), `HTTP ${pdf.status}`);

    const patientWrite = await p('POST', `/patients/me/prescriptions`, { items: [{ name: 'Anything' }] });
    check('patient cannot write a prescription', patientWrite.status === 403, `HTTP ${patientWrite.status}`);
  }

  console.log('\n--- Doctor: alert acknowledgement flow ---');
  {
    const alerts = await d('GET', `/doctor/alerts?status=open`);
    const first = alerts.body?.items?.[0];
    check('open alerts listed', Boolean(first), `${alerts.body?.items?.length} open`);

    if (first) {
      const ack = await d('POST', `/doctor/alerts/${first.id}/acknowledge`);
      check('alert acknowledged', ack.body?.alert?.status === 'acknowledged');
      const res = await d('POST', `/doctor/alerts/${first.id}/resolve`, { notes: 'Contacted patient by phone.' });
      check('alert resolved', res.body?.alert?.status === 'resolved');
    }
  }

  console.log(`\n  ${passed} passed, ${failed} failed\n`);
  process.exit(failed ? 1 : 0);
}

/** Next weekday inside clinic hours, as YYYY-MM-DD. */
function nextWeekday() {
  const d = new Date();
  d.setDate(d.getDate() + 3);
  return d.toISOString().slice(0, 10);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});

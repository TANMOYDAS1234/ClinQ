import { Router } from 'express';
import dayjs from 'dayjs';
import { z } from 'zod';
import { requireAuth, resolvePatientScope, requireClinician } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { Prescription } from '../models/Prescription.js';
import { Medication } from '../models/Medication.js';
import { User } from '../models/User.js';
import { notifyPatientOfPrescription } from '../services/notifications.js';
import { buildSchedule } from '../services/medicationSchedule.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { env } from '../config/env.js';
import { paged, pageParams } from '../utils/pagination.js';

const router = Router({ mergeParams: true });
router.use(requireAuth, resolvePatientScope);

/** Sequential per-year reference, e.g. AKD-2026-000412. */
async function nextReference() {
  const year = dayjs().year();
  const count = await Prescription.countDocuments({
    referenceNo: new RegExp(`^AKD-${year}-`),
  });
  return `AKD-${year}-${String(count + 1).padStart(6, '0')}`;
}

router.get(
  '/',
  validate({ query: pageParams }),
  audit('read', 'Prescription'),
  asyncHandler(async (req, res) => {
    const { page, limit, skip } = q(req);
    const filter = { patient: req.patientId };
    const [items, total] = await Promise.all([
      Prescription.find(filter).sort({ issuedOn: -1 }).skip(skip).limit(limit).populate('doctor', 'name').lean(),
      Prescription.countDocuments(filter),
    ]);
    res.json(paged(items.map(serialise), { page, limit, total }));
  }),
);

router.get(
  '/:id',
  audit('read', 'Prescription'),
  asyncHandler(async (req, res) => {
    const p = await Prescription.findOne({ _id: req.params.id, patient: req.patientId })
      .populate('doctor', 'name')
      .lean();
    if (!p) throw notFound('Prescription not found');
    res.json({ prescription: serialise(p) });
  }),
);

router.post(
  '/',
  requireClinician,
  validate({
    body: z.object({
      appointmentId: z.string().optional(),
      issuedOn: z.coerce.date().default(() => new Date()),
      validUntil: z.coerce.date().optional(),
      diagnosis: z.array(z.string().max(300)).max(20).default([]),
      items: z
        .array(
          z.object({
            name: z.string().min(1).max(160),
            strength: z.string().max(60).optional(),
            dose: z.string().max(60).optional(),
            frequency: z.string().max(120).optional(),
            durationDays: z.number().int().min(1).max(365).optional(),
            relationToMeal: z.enum(['before_meal', 'after_meal', 'with_meal', 'any']).default('any'),
            instructions: z.string().max(400).optional(),
          }),
        )
        .min(1, 'A prescription needs at least one medicine'),
      labTestsAdvised: z.array(z.string().max(200)).max(30).default([]),
      generalAdvice: z.string().max(4000).optional(),
      followUpOn: z.coerce.date().optional(),
      supersedes: z.string().optional(),
      // Mirror the prescribed items into the patient's medication tracker.
      syncToMedications: z.boolean().default(true),
    }),
  }),
  audit('create', 'Prescription'),
  asyncHandler(async (req, res) => {
    const { syncToMedications, appointmentId, ...body } = req.body;

    const prescription = await Prescription.create({
      ...body,
      patient: req.patientId,
      doctor: req.user._id,
      appointment: appointmentId,
      referenceNo: await nextReference(),
    });

    if (body.supersedes) {
      await Prescription.updateOne({ _id: body.supersedes }, { isActive: false });
    }

    if (syncToMedications) {
      await syncMedications(prescription, req.patientId, req.user._id);
    }

    // Let the patient know at once so their Medicines tab and reminders refresh.
    notifyPatientOfPrescription(req.patientId, req.user).catch(() => {});

    res.status(201).json({ prescription: serialise(await prescription.populate('doctor', 'name')) });
  }),
);

async function syncMedications(prescription, patientId, doctorId) {
  const profile = await PatientProfile.findOne({ user: patientId }).select('mealTimes').lean();
  const mealTimes = profile?.mealTimes;
  for (const item of prescription.items) {
    await Medication.findOneAndUpdate(
      { patient: patientId, name: item.name, isActive: true },
      {
        $set: {
          patient: patientId,
          name: item.name,
          strength: item.strength,
          dose: item.dose,
          form: /insulin/i.test(item.name) ? 'insulin' : 'tablet',
          schedule: buildSchedule(item.frequency, mealTimes, item.relationToMeal),
          startDate: prescription.issuedOn,
          endDate: item.durationDays
            ? dayjs(prescription.issuedOn).add(item.durationDays, 'day').toDate()
            : undefined,
          instructions: item.instructions,
          prescribedBy: doctorId,
          prescription: prescription._id,
          isActive: true,
        },
      },
      { upsert: true, setDefaultsOnInsert: true },
    );
  }
}

/**
 * Printable prescription. Served as styled HTML rather than a binary PDF: the
 * mobile client renders it in a webview and uses the platform print dialog to
 * save a PDF, which avoids shipping a headless-Chrome dependency server-side.
 */
router.get(
  '/:id/pdf',
  audit('export', 'Prescription'),
  asyncHandler(async (req, res) => {
    const p = await Prescription.findOne({ _id: req.params.id, patient: req.patientId })
      .populate('doctor', 'name')
      .lean();
    if (!p) throw notFound('Prescription not found');

    const patient = await User.findById(req.patientId).select('name phone dateOfBirth gender').lean();
    res.type('html').send(renderPrescriptionHtml(p, patient));
  }),
);

const esc = (s) =>
  String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);

function renderPrescriptionHtml(p, patient) {
  const age = patient?.dateOfBirth ? dayjs().diff(dayjs(patient.dateOfBirth), 'year') : null;

  return `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Prescription ${esc(p.referenceNo)}</title>
<style>
  *{box-sizing:border-box} body{font-family:system-ui,-apple-system,'Segoe UI',sans-serif;margin:0;padding:24px;color:#0f172a;line-height:1.5}
  .head{border-bottom:3px solid #0f766e;padding-bottom:12px;margin-bottom:16px}
  .clinic{font-size:22px;font-weight:700;color:#0f766e} .doc{font-size:14px;color:#475569}
  .meta{display:flex;justify-content:space-between;flex-wrap:wrap;gap:8px;font-size:14px;margin-bottom:16px}
  .box{background:#f8fafc;border:1px solid #e2e8f0;border-radius:8px;padding:12px;margin-bottom:16px}
  h3{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:#0f766e;margin:0 0 8px}
  table{width:100%;border-collapse:collapse;font-size:14px} th,td{text-align:left;padding:8px;border-bottom:1px solid #e2e8f0;vertical-align:top}
  th{background:#f1f5f9;font-size:12px;text-transform:uppercase;letter-spacing:.04em}
  .rx{font-size:30px;font-weight:700;color:#0f766e;margin:0 0 4px}
  ul{margin:0;padding-left:20px} .foot{margin-top:32px;display:flex;justify-content:space-between;align-items:flex-end;font-size:13px;color:#475569}
  .sign{border-top:1px solid #0f172a;padding-top:6px;min-width:200px;text-align:center}
  @media print{body{padding:0} .noprint{display:none}}
</style></head>
<body>
  <div class="head">
    <div class="clinic">${esc(env.CLINIC_NAME)}</div>
    <div class="doc">${esc(p.doctor?.name ?? env.DOCTOR_DISPLAY_NAME)} — Consultant Physician &amp; Diabetologist</div>
  </div>

  <div class="meta">
    <div><strong>${esc(patient?.name)}</strong>${age ? ` · ${age} yrs` : ''}${patient?.gender && patient.gender !== 'undisclosed' ? ` · ${esc(patient.gender)}` : ''}<br>
      <span style="color:#475569">${esc(patient?.phone)}</span></div>
    <div style="text-align:right">Ref: <strong>${esc(p.referenceNo)}</strong><br>
      <span style="color:#475569">${dayjs(p.issuedOn).format('DD MMM YYYY')}</span></div>
  </div>

  ${p.diagnosis?.length ? `<div class="box"><h3>Diagnosis</h3><ul>${p.diagnosis.map((d) => `<li>${esc(d)}</li>`).join('')}</ul></div>` : ''}

  <p class="rx">℞</p>
  <table>
    <thead><tr><th>Medicine</th><th>Dose</th><th>Frequency</th><th>Duration</th></tr></thead>
    <tbody>
      ${p.items
        .map(
          (i) => `<tr>
        <td><strong>${esc(i.name)}</strong>${i.strength ? `<br><span style="color:#475569">${esc(i.strength)}</span>` : ''}
          ${i.instructions ? `<br><em style="color:#475569;font-size:13px">${esc(i.instructions)}</em>` : ''}</td>
        <td>${esc(i.dose ?? '—')}</td>
        <td>${esc(i.frequency ?? '—')}<br><span style="color:#475569;font-size:12px">${esc((i.relationToMeal ?? 'any').replace(/_/g, ' '))}</span></td>
        <td>${i.durationDays ? `${i.durationDays} days` : '—'}</td>
      </tr>`,
        )
        .join('')}
    </tbody>
  </table>

  ${p.labTestsAdvised?.length ? `<div class="box" style="margin-top:16px"><h3>Investigations advised</h3><ul>${p.labTestsAdvised.map((t) => `<li>${esc(t)}</li>`).join('')}</ul></div>` : ''}
  ${p.generalAdvice ? `<div class="box"><h3>Advice</h3><div>${esc(p.generalAdvice).replace(/\n/g, '<br>')}</div></div>` : ''}
  ${p.followUpOn ? `<div class="box"><h3>Follow-up</h3><div>${dayjs(p.followUpOn).format('DD MMM YYYY')}</div></div>` : ''}

  <div class="foot">
    <div>This prescription is valid${p.validUntil ? ` until ${dayjs(p.validUntil).format('DD MMM YYYY')}` : ''}.<br>
      Do not change any dose without consulting your doctor.</div>
    <div class="sign">${esc(p.doctor?.name ?? env.DOCTOR_DISPLAY_NAME)}</div>
  </div>

  <button class="noprint" onclick="window.print()" style="margin-top:24px;padding:12px 20px;background:#0f766e;color:#fff;border:0;border-radius:8px;font-size:16px">Print / Save as PDF</button>
</body></html>`;
}

function serialise(p) {
  return {
    id: p._id,
    referenceNo: p.referenceNo,
    issuedOn: p.issuedOn,
    validUntil: p.validUntil ?? null,
    doctorName: p.doctor?.name ?? null,
    diagnosis: p.diagnosis ?? [],
    items: p.items ?? [],
    labTestsAdvised: p.labTestsAdvised ?? [],
    generalAdvice: p.generalAdvice ?? null,
    followUpOn: p.followUpOn ?? null,
    isActive: p.isActive,
    pdfUrl: `/api/v1/patients/${p.patient}/prescriptions/${p._id}/pdf`,
  };
}

export default router;

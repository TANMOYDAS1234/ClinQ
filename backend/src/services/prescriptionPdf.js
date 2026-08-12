import PDFDocument from 'pdfkit';
import sharp from 'sharp';
import path from 'node:path';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import dayjs from 'dayjs';
import utc from 'dayjs/plugin/utc.js';
import timezone from 'dayjs/plugin/timezone.js';
import { env } from '../config/env.js';
import { MediaAsset } from '../models/MediaAsset.js';
import { Prescription } from '../models/Prescription.js';
import { PatientProfile } from '../models/PatientProfile.js';
import { User } from '../models/User.js';

dayjs.extend(utc);
dayjs.extend(timezone);

// The clinic is in India; render every date/time in its wall-clock time so a
// server running in UTC does not print a prescription "issued" 5.5 hours early.
const fmt = (d, f) => dayjs(d).tz(env.CLINIC_TZ).format(f);

const TEAL = '#0f766e';
const SLATE = '#475569';
const INK = '#0f172a';
const LINE = '#e2e8f0';
const WASH = '#f1f5f9';

/**
 * Render a prescription to a PDF buffer (pdfkit — no headless browser). Laid out
 * as a single-doctor clinic letterhead: header, patient block, complaint,
 * diagnosis, the Rx medicines table, investigations, advice, follow-up, and a
 * signature block (image when the doctor has uploaded one, otherwise a line).
 */
export function buildPrescriptionPdf({ prescription: p, patient, doctor, profile, signatureImage }) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A4', margin: 48 });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const M = 48;
    const right = doc.page.width - M;
    const contentW = doc.page.width - M * 2;
    const bottom = doc.page.height - M;

    // --- Header -----------------------------------------------------------
    doc.fillColor(TEAL).font('Helvetica-Bold').fontSize(20).text(env.CLINIC_NAME, M, M, { width: contentW });
    const doctorName = doctor?.name ?? env.DOCTOR_DISPLAY_NAME;
    const credentials = [doctor?.qualifications, doctor?.specialty ?? 'Consultant Physician & Diabetologist']
      .filter(Boolean)
      .join(', ');
    doc.fillColor(SLATE).font('Helvetica').fontSize(10.5).text(`${doctorName}${credentials ? ` — ${credentials}` : ''}`, {
      width: contentW,
    });
    const contactBits = [
      doctor?.registrationNo ? `Reg. No: ${doctor.registrationNo}` : null,
      env.CLINIC_EMERGENCY_PHONE && !env.CLINIC_EMERGENCY_PHONE.includes('0000')
        ? `Ph: ${env.CLINIC_EMERGENCY_PHONE}`
        : null,
    ].filter(Boolean);
    if (contactBits.length) doc.fontSize(9.5).fillColor(SLATE).text(contactBits.join('   ·   '), { width: contentW });

    doc.moveDown(0.4);
    let y = doc.y;
    doc.moveTo(M, y).lineTo(right, y).lineWidth(2).strokeColor(TEAL).stroke();
    y += 12;

    // --- Patient block ----------------------------------------------------
    const age = patient?.dateOfBirth ? dayjs().diff(dayjs(patient.dateOfBirth), 'year') : null;
    const demo = [age != null ? `${age} yrs` : null, patient?.gender && patient.gender !== 'undisclosed' ? cap(patient.gender) : null]
      .filter(Boolean)
      .join(' · ');

    const boxTop = y;
    doc.font('Helvetica-Bold').fontSize(13).fillColor(INK).text(patient?.name ?? '—', M, y + 2, { width: contentW * 0.62 });
    let ly = doc.y;
    doc.font('Helvetica').fontSize(10).fillColor(SLATE);
    if (demo) { doc.text(demo, M, ly, { width: contentW * 0.62 }); ly = doc.y; }
    if (patient?.phone) { doc.text(patient.phone, M, ly, { width: contentW * 0.62 }); ly = doc.y; }
    if (profile?.address) { doc.text(profile.address, M, ly, { width: contentW * 0.62 }); ly = doc.y; }

    // Right column: reference + issue date/time.
    doc.font('Helvetica').fontSize(10).fillColor(SLATE);
    doc.text(`Ref: ${p.referenceNo}`, M + contentW * 0.62, boxTop + 2, { width: contentW * 0.38, align: 'right' });
    doc.text(fmt(p.issuedOn, 'DD MMM YYYY, hh:mm A'), { width: contentW * 0.38, align: 'right' });

    y = Math.max(ly, doc.y) + 10;

    // --- Chief complaint --------------------------------------------------
    if (p.complaint || profile?.chiefComplaint) {
      y = labelledBlock(doc, 'Chief complaint', String(p.complaint || profile.chiefComplaint), M, y, contentW);
    }

    // --- Diagnosis --------------------------------------------------------
    if (p.diagnosis?.length) {
      y = labelledBlock(doc, 'Diagnosis', p.diagnosis.map((d) => `•  ${d}`).join('\n'), M, y, contentW);
    }

    // --- Rx symbol + medicines table -------------------------------------
    doc.font('Helvetica-Bold').fontSize(24).fillColor(TEAL).text('℞', M, y);
    y = doc.y + 4;

    const cols = [
      { title: 'Medicine', w: contentW * 0.44 },
      { title: 'Dose', w: contentW * 0.16 },
      { title: 'Frequency', w: contentW * 0.24 },
      { title: 'Duration', w: contentW * 0.16 },
    ];
    y = tableHeader(doc, cols, M, y);
    for (const item of p.items ?? []) {
      y = ensureSpace(doc, y, 40, M, () => tableHeader(doc, cols, M, doc.y));
      y = medicineRow(doc, cols, item, M, y);
    }

    y += 8;

    // --- Investigations ---------------------------------------------------
    if (p.labTestsAdvised?.length) {
      y = ensureSpace(doc, y, 60, M);
      y = labelledBlock(doc, 'Investigations advised', p.labTestsAdvised.map((t) => `•  ${t}`).join('\n'), M, y, contentW);
    }

    // --- Advice -----------------------------------------------------------
    if (p.generalAdvice) {
      y = ensureSpace(doc, y, 60, M);
      y = labelledBlock(doc, 'Advice', p.generalAdvice, M, y, contentW);
    }

    // --- Follow-up --------------------------------------------------------
    if (p.followUpOn) {
      y = ensureSpace(doc, y, 50, M);
      y = labelledBlock(doc, 'Follow-up', fmt(p.followUpOn, 'DD MMM YYYY'), M, y, contentW);
    }

    // --- Signature block --------------------------------------------------
    y = ensureSpace(doc, y, 130, M);
    const sigW = 200;
    const sigX = right - sigW;
    let sigY = Math.max(y + 24, bottom - 96);
    if (signatureImage) {
      try {
        doc.image(signatureImage, sigX + (sigW - 150) / 2, sigY - 4, { fit: [150, 52], align: 'center' });
      } catch {
        // A bad image should never sink the whole prescription.
      }
    }
    sigY += 54;
    doc.moveTo(sigX, sigY).lineTo(sigX + sigW, sigY).lineWidth(1).strokeColor(INK).stroke();
    doc.font('Helvetica-Bold').fontSize(11).fillColor(INK).text(doctorName, sigX, sigY + 5, { width: sigW, align: 'center' });
    if (credentials) {
      doc.font('Helvetica').fontSize(8.5).fillColor(SLATE).text(credentials, sigX, doc.y, { width: sigW, align: 'center' });
    }

    // --- Footer note ------------------------------------------------------
    doc
      .font('Helvetica')
      .fontSize(8.5)
      .fillColor(SLATE)
      .text(
        `This prescription is valid${p.validUntil ? ` until ${fmt(p.validUntil, 'DD MMM YYYY')}` : ''}. ` +
          'Do not change any dose without consulting your doctor.',
        M,
        bottom - 18,
        { width: contentW * 0.6 },
      );

    doc.end();
  });
}

function cap(s) {
  return s ? s[0].toUpperCase() + s.slice(1) : s;
}

/** A titled block: small teal uppercase label over a light-washed body box. */
function labelledBlock(doc, title, body, x, y, w) {
  doc.font('Helvetica-Bold').fontSize(9).fillColor(TEAL).text(title.toUpperCase(), x, y, { characterSpacing: 0.5 });
  const ty = doc.y + 3;
  doc.font('Helvetica').fontSize(10.5).fillColor(INK);
  const h = doc.heightOfString(body, { width: w - 20 });
  doc.rect(x, ty, w, h + 16).fillColor(WASH).fill();
  doc.fillColor(INK).text(body, x + 10, ty + 8, { width: w - 20 });
  return ty + h + 16 + 10;
}

function tableHeader(doc, cols, x, y) {
  doc.rect(x, y, cols.reduce((a, c) => a + c.w, 0), 22).fillColor(WASH).fill();
  let cx = x;
  doc.font('Helvetica-Bold').fontSize(9).fillColor(SLATE);
  for (const c of cols) {
    doc.text(c.title.toUpperCase(), cx + 6, y + 7, { width: c.w - 12, characterSpacing: 0.4 });
    cx += c.w;
  }
  return y + 22;
}

function medicineRow(doc, cols, item, x, y) {
  const relation = (item.relationToMeal ?? 'any').replace(/_/g, ' ');
  const nameW = cols[0].w - 12;
  doc.font('Helvetica-Bold').fontSize(10.5).fillColor(INK);
  const nameH = doc.heightOfString(item.name ?? '—', { width: nameW });
  let subH = 0;
  const sub = [item.strength, item.instructions].filter(Boolean).join(' · ');
  if (sub) {
    doc.font('Helvetica').fontSize(9);
    subH = doc.heightOfString(sub, { width: nameW }) + 2;
  }
  const freq = `${item.frequency ?? '—'}${relation !== 'any' ? `\n${relation}` : ''}`;
  doc.font('Helvetica').fontSize(10);
  const freqH = doc.heightOfString(freq, { width: cols[2].w - 12 });
  const rowH = Math.max(nameH + subH, freqH, 14) + 12;

  let cx = x;
  // Medicine
  doc.font('Helvetica-Bold').fontSize(10.5).fillColor(INK).text(item.name ?? '—', cx + 6, y + 6, { width: nameW });
  if (sub) doc.font('Helvetica').fontSize(9).fillColor(SLATE).text(sub, cx + 6, y + 6 + nameH + 1, { width: nameW });
  cx += cols[0].w;
  // Dose
  doc.font('Helvetica').fontSize(10).fillColor(INK).text(item.dose ?? '—', cx + 6, y + 6, { width: cols[1].w - 12 });
  cx += cols[1].w;
  // Frequency (+ relation to meal)
  doc.fillColor(INK).text(item.frequency ?? '—', cx + 6, y + 6, { width: cols[2].w - 12 });
  if (relation !== 'any') doc.fontSize(8.5).fillColor(SLATE).text(relation, cx + 6, doc.y, { width: cols[2].w - 12 });
  cx += cols[2].w;
  // Duration
  doc.fontSize(10).fillColor(INK).text(item.durationDays ? `${item.durationDays} days` : '—', cx + 6, y + 6, {
    width: cols[3].w - 12,
  });

  const totalW = cols.reduce((a, c) => a + c.w, 0);
  doc.moveTo(x, y + rowH).lineTo(x + totalW, y + rowH).lineWidth(0.5).strokeColor(LINE).stroke();
  return y + rowH;
}

/** Add a page when `need` points won't fit; optionally redraw a table header. */
function ensureSpace(doc, y, need, x, onNewPage) {
  const bottom = doc.page.height - 48;
  if (y + need <= bottom) return y;
  doc.addPage();
  return onNewPage ? onNewPage() : doc.page.margins.top;
}

/**
 * Return the stored prescription PDF, generating and caching it as a
 * `prescription_pdf` MediaAsset (owned by the patient) on first request.
 * Prescriptions are immutable, so the document only ever needs building once.
 * Returns `{ asset, filePath }`.
 */
export async function ensurePrescriptionPdf(prescription) {
  if (prescription.pdfFile) {
    const existing = await MediaAsset.findOne({ _id: prescription.pdfFile, deletedAt: null });
    if (existing) return { asset: existing, filePath: await assetPath(existing) };
  }

  const [patient, doctor, profile] = await Promise.all([
    User.findById(prescription.patient).select('name phone dateOfBirth gender').lean(),
    prescription.doctor
      ? User.findById(prescription.doctor).select('name qualifications specialty registrationNo signatureAssetId').lean()
      : null,
    PatientProfile.findOne({ user: prescription.patient }).select('address chiefComplaint').lean(),
  ]);

  const signatureImage = await loadSignature(doctor?.signatureAssetId);
  const buffer = await buildPrescriptionPdf({ prescription, patient, doctor, profile, signatureImage });

  const root = await uploadRoot();
  const key = `${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.pdf`;
  const filePath = path.join(root, key);
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  await fs.writeFile(filePath, buffer);

  const asset = await MediaAsset.create({
    owner: prescription.patient,
    uploadedBy: prescription.doctor ?? prescription.patient,
    kind: 'prescription_pdf',
    storageKey: key,
    originalName: `${prescription.referenceNo}.pdf`,
    mimeType: 'application/pdf',
    sizeBytes: buffer.length,
  });
  await Prescription.updateOne({ _id: prescription._id }, { pdfFile: asset._id });
  return { asset, filePath };
}

async function uploadRoot() {
  const dir = path.resolve(process.cwd(), env.UPLOAD_DIR);
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

async function assetPath(asset) {
  return path.join(await uploadRoot(), asset.storageKey);
}

/** The doctor's signature image bytes, if they have uploaded one. */
async function loadSignature(signatureAssetId) {
  if (!signatureAssetId) return null;
  const asset = await MediaAsset.findOne({ _id: signatureAssetId, deletedAt: null }).lean();
  if (!asset) return null;
  try {
    const raw = await fs.readFile(path.join(await uploadRoot(), asset.storageKey));
    // pdfkit embeds only JPEG/PNG, but uploads are stored as WebP — convert, and
    // keep any transparency so a cut-out signature overlays the line cleanly.
    return await sharp(raw).png().toBuffer();
  } catch {
    return null;
  }
}

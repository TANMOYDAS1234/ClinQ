import { Router } from 'express';
import multer from 'multer';
import sharp from 'sharp';
import path from 'node:path';
import fs from 'node:fs/promises';
import crypto from 'node:crypto';
import { z } from 'zod';
import { requireAuth } from '../middleware/auth.js';
import { validate } from '../middleware/validate.js';
import { asyncHandler, badRequest, notFound, forbidden } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { MediaAsset } from '../models/MediaAsset.js';
import { ROLES } from '../models/User.js';
import { env } from '../config/env.js';
import { logger } from '../config/logger.js';

const router = Router();

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: env.MAX_UPLOAD_MB * 1024 * 1024, files: 1 },
  fileFilter: (req, file, cb) => {
    if (!ALLOWED_MIME.has(file.mimetype)) {
      return cb(badRequest(`Unsupported file type: ${file.mimetype}. Upload a JPEG, PNG, WebP or PDF.`));
    }
    cb(null, true);
  },
});

async function uploadRoot() {
  const dir = path.resolve(process.cwd(), env.UPLOAD_DIR);
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

router.post(
  '/',
  requireAuth,
  upload.single('file'),
  validate({
    body: z.object({
      kind: z.enum(['foot_photo', 'retinal_report', 'lab_report', 'prescription_pdf', 'meal_photo', 'avatar', 'other']),
      patientId: z.string().optional(),
    }),
  }),
  audit('create', 'MediaAsset'),
  asyncHandler(async (req, res) => {
    if (!req.file) throw badRequest('No file was uploaded');

    // Clinicians may upload on a patient's behalf; patients only for themselves.
    let owner = req.user._id;
    if (req.body.patientId && req.user.role !== ROLES.PATIENT) owner = req.body.patientId;

    const root = await uploadRoot();
    const isPdf = req.file.mimetype === 'application/pdf';
    const ext = isPdf ? 'pdf' : 'webp';
    const key = `${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.${ext}`;
    const fullPath = path.join(root, key);
    await fs.mkdir(path.dirname(fullPath), { recursive: true });

    let width = null;
    let height = null;
    let buffer = req.file.buffer;
    let mimeType = req.file.mimetype;

    if (!isPdf) {
      // Normalise to WebP: strips EXIF (which can carry GPS location of a
      // patient's home) and keeps clinical photos to a sane size.
      const image = sharp(req.file.buffer, { failOn: 'none' }).rotate();
      const meta = await image.metadata();
      width = meta.width ?? null;
      height = meta.height ?? null;
      buffer = await image.resize({ width: 2000, height: 2000, fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 88 })
        .toBuffer();
      mimeType = 'image/webp';
    }

    await fs.writeFile(fullPath, buffer);

    const asset = await MediaAsset.create({
      owner,
      uploadedBy: req.user._id,
      kind: req.body.kind,
      storageKey: key,
      originalName: req.file.originalname?.slice(0, 260),
      mimeType,
      sizeBytes: buffer.length,
      width,
      height,
    });

    res.status(201).json({
      id: asset._id,
      kind: asset.kind,
      mimeType: asset.mimeType,
      sizeBytes: asset.sizeBytes,
      width: asset.width,
      height: asset.height,
      url: `/api/v1/uploads/${asset._id}/raw`,
      createdAt: asset.createdAt,
    });
  }),
);

router.get(
  '/:id/raw',
  requireAuth,
  audit('read', 'MediaAsset'),
  asyncHandler(async (req, res) => {
    const asset = await MediaAsset.findById(req.params.id);
    if (!asset || asset.deletedAt) throw notFound('File not found');

    const isOwner = asset.owner.toString() === req.user._id.toString();
    const isClinician = req.user.role !== ROLES.PATIENT;
    if (!isOwner && !isClinician) throw forbidden('You do not have access to this file');

    req.patientId = asset.owner;

    const root = await uploadRoot();
    const fullPath = path.join(root, asset.storageKey);

    try {
      await fs.access(fullPath);
    } catch {
      logger.error({ assetId: asset._id.toString(), key: asset.storageKey }, 'media file missing from disk');
      throw notFound('File is no longer available');
    }

    res.type(asset.mimeType);
    res.setHeader('Cache-Control', 'private, max-age=3600');
    res.sendFile(fullPath);
  }),
);

router.delete(
  '/:id',
  requireAuth,
  audit('update', 'MediaAsset'),
  asyncHandler(async (req, res) => {
    const asset = await MediaAsset.findById(req.params.id);
    if (!asset) throw notFound('File not found');
    if (asset.owner.toString() !== req.user._id.toString() && req.user.role === ROLES.PATIENT) {
      throw forbidden('You do not have access to this file');
    }
    // Soft delete only — the bytes stay for the medical record.
    asset.deletedAt = new Date();
    await asset.save();
    res.status(204).end();
  }),
);

/** Loads assets as base64 for the vision model. */
export async function loadAssetsForAi(assetIds, { max = 3 } = {}) {
  const assets = await MediaAsset.find({ _id: { $in: assetIds }, deletedAt: null }).limit(max).lean();
  const root = await uploadRoot();

  const out = [];
  for (const a of assets) {
    if (!a.mimeType.startsWith('image/')) continue;
    try {
      const buf = await fs.readFile(path.join(root, a.storageKey));
      // Gemini handles JPEG more reliably than WebP for vision input.
      const jpeg = await sharp(buf).jpeg({ quality: 85 }).toBuffer();
      out.push({ mimeType: 'image/jpeg', base64: jpeg.toString('base64'), assetId: a._id });
    } catch (err) {
      logger.warn({ err: err?.message, assetId: a._id.toString() }, 'could not load asset for AI');
    }
  }
  return out;
}

export default router;

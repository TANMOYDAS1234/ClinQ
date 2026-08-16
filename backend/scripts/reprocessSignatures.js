/**
 * Re-cuts signatures uploaded before the background removal existed.
 *
 * The paper is stripped at upload time, so a signature already on file keeps
 * whatever it was stored as — a photograph of a sheet of paper. That prints on
 * the prescription as a grey rectangle and shows in the profile preview with
 * the paper still attached, which is exactly what it looks like.
 *
 * This re-runs the same cut-out over the stored file and writes a new asset, so
 * nothing has to be re-photographed.
 *
 * Reports by default; writes only with --apply.
 *
 *   node scripts/reprocessSignatures.js            # who has one, and its format
 *   node scripts/reprocessSignatures.js --apply    # re-cut them
 */
import path from 'node:path';
import fs from 'node:fs/promises';
import mongoose from 'mongoose';
import crypto from 'node:crypto';
import { env } from '../src/config/env.js';
import { User, ROLES } from '../src/models/User.js';
import { MediaAsset } from '../src/models/MediaAsset.js';
import { assessSignature, makeSignatureTransparent } from '../src/services/signature.js';

const apply = process.argv.includes('--apply');

async function uploadRoot() {
  const dir = path.resolve(process.cwd(), env.UPLOAD_DIR);
  await fs.mkdir(dir, { recursive: true });
  return dir;
}

async function main() {
  await mongoose.connect(env.MONGODB_URI);

  const doctors = await User.find({
    role: { $ne: ROLES.PATIENT },
    signatureAssetId: { $ne: null },
  })
    .select('name signatureAssetId')
    .lean();

  if (doctors.length === 0) {
    console.log('Nobody has a signature on file.');
    return;
  }

  const root = await uploadRoot();

  for (const d of doctors) {
    const asset = await MediaAsset.findById(d.signatureAssetId).lean();
    if (!asset) {
      console.log(`${d.name}: signature asset missing`);
      continue;
    }

    // A PNG that is already transparent has been through this once.
    const already = asset.mimeType === 'image/png';
    console.log(`${d.name}: ${asset.mimeType}  ${asset.storageKey}${already ? '  (already cut out)' : ''}`);
    if (already || !apply) continue;

    try {
      const raw = await fs.readFile(path.join(root, asset.storageKey));
      const verdict = await assessSignature(raw);
      if (!verdict.ok) {
        console.log(`   skipped — ${verdict.reason}`);
        continue;
      }

      const cut = await makeSignatureTransparent(raw);
      const key = `${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}.png`;
      const full = path.join(root, key);
      await fs.mkdir(path.dirname(full), { recursive: true });
      await fs.writeFile(full, cut.buffer);

      // A new asset rather than an overwrite: the original stays on disk, so a
      // bad cut can be undone by pointing the user back at it.
      const fresh = await MediaAsset.create({
        owner: asset.owner,
        uploadedBy: asset.uploadedBy,
        kind: 'signature',
        storageKey: key,
        originalName: asset.originalName,
        mimeType: 'image/png',
        sizeBytes: cut.buffer.length,
        width: cut.width,
        height: cut.height,
      });
      await User.updateOne({ _id: d._id }, { signatureAssetId: fresh._id });
      console.log(`   re-cut -> ${key} (${cut.buffer.length} bytes)`);
    } catch (err) {
      console.log(`   failed — ${err.message}`);
    }
  }

  if (!apply) console.log('\nNothing written. Re-run with --apply to re-cut them.');
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());

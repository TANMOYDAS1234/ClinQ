/**
 * Inspects — and optionally retries — the automatic reading of uploaded lab
 * reports.
 *
 * The analysis runs in the background of an upload, so when it fails there is
 * nothing on screen to say why: the report just sits there and the patient's
 * HbA1c never moves. This prints the state of every recent report, and can
 * re-run the ones that never completed.
 *
 *   node scripts/labAnalysis.js                 # what happened to the last 20
 *   node scripts/labAnalysis.js --retry         # re-run pending/failed ones
 *   node scripts/labAnalysis.js --retry --id <labResultId>
 *   node scripts/labAnalysis.js --limit 50
 */
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { LabResult } from '../src/models/LabResult.js';
import { MediaAsset } from '../src/models/MediaAsset.js';
import { User } from '../src/models/User.js';
import { Hba1cRecord } from '../src/models/Hba1cRecord.js';
import { analyseLabResult } from '../src/services/ai/labReport.js';

const args = process.argv.slice(2);
const retry = args.includes('--retry');
const idArg = args[args.indexOf('--id') + 1];
const limitArg = Number(args[args.indexOf('--limit') + 1]);
const limit = Number.isFinite(limitArg) && limitArg > 0 ? limitArg : 20;

async function main() {
  await mongoose.connect(env.MONGODB_URI);

  const filter = args.includes('--id') && idArg ? { _id: idArg } : {};
  const results = await LabResult.find(filter)
    .sort({ createdAt: -1 })
    .limit(limit)
    .populate('patient', 'name')
    .lean();

  if (results.length === 0) {
    console.log('No lab results found.');
    return;
  }

  console.log(`${results.length} report(s), newest first:\n`);
  for (const r of results) {
    const asset = r.photo ? await MediaAsset.findById(r.photo).select('mimeType storageKey').lean() : null;
    const a = r.analysis ?? {};
    console.log(`  ${String(r._id)}`);
    console.log(`    patient : ${r.patient?.name ?? '(unknown)'}`);
    console.log(`    test    : ${r.testName}`);
    console.log(`    uploaded: ${new Date(r.createdAt).toISOString()}`);
    console.log(`    file    : ${asset ? `${asset.mimeType}  ${asset.storageKey}` : '(no file)'}`);
    console.log(`    status  : ${a.status ?? '(never set — the analysis did not start)'}`);
    if (a.summary) console.log(`    summary : ${a.summary.slice(0, 120)}`);
    if (a.hba1cPercent != null) console.log(`    HbA1c   : ${a.hba1cPercent}%`);
    if (a.analysedAt) console.log(`    read at : ${new Date(a.analysedAt).toISOString()}`);
    console.log('');
  }

  if (!retry) {
    console.log('Nothing re-run. Pass --retry to analyse the pending/failed ones.');
    return;
  }

  const toRetry = results.filter(
    (r) => r.photo && (r.analysis?.status == null || ['pending', 'failed'].includes(r.analysis.status)),
  );
  if (toRetry.length === 0) {
    console.log('Nothing to retry — every report has been read.');
    return;
  }

  console.log(`Re-running ${toRetry.length}…\n`);
  for (const r of toRetry) {
    // Awaited one at a time, unlike the upload path: this is a maintenance run,
    // and a readable log matters more than finishing quickly.
    await analyseLabResult(r._id);
    const after = await LabResult.findById(r._id).select('analysis').lean();
    const hba1c = await Hba1cRecord.findOne({ patient: r.patient?._id ?? r.patient })
      .sort({ testedOn: -1 })
      .select('percentage testedOn')
      .lean();
    console.log(
      `  ${String(r._id)} -> ${after?.analysis?.status ?? 'unknown'}` +
        `${after?.analysis?.hba1cPercent != null ? ` (HbA1c ${after.analysis.hba1cPercent}%)` : ''}` +
        `${hba1c ? ` | latest on record: ${hba1c.percentage}% ${new Date(hba1c.testedOn).toISOString().slice(0, 10)}` : ''}`,
    );
    if (after?.analysis?.summary) console.log(`      ${after.analysis.summary.slice(0, 140)}`);
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());

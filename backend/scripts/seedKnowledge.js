/**
 * Seeds the doctor-approved knowledge base and generates embeddings.
 *
 *   npm run seed:knowledge            # insert/update, embed, mark approved
 *   npm run seed:knowledge -- --dry   # show what would happen, touch nothing
 *
 * Safe to re-run: chunks are matched on docId and updated in place.
 */
import mongoose from 'mongoose';
import { connectDb, disconnectDb } from '../src/config/db.js';
import { KnowledgeChunk } from '../src/models/KnowledgeChunk.js';
import { User, ROLES } from '../src/models/User.js';
import { KNOWLEDGE_SEED } from '../src/knowledge/seedContent.js';
import { embed } from '../src/services/ai/gemini.js';
import { env } from '../src/config/env.js';
import { logger } from '../src/config/logger.js';

const dryRun = process.argv.includes('--dry');
const skipEmbeddings = process.argv.includes('--no-embed');

async function main() {
  await connectDb();

  const doctor = await User.findOne({ role: ROLES.DOCTOR }).lean();
  if (!doctor && !dryRun) {
    logger.warn('no doctor account found — run `npm run seed` first so approvals are attributable');
  }

  let created = 0;
  let updated = 0;
  let embedded = 0;
  let failed = 0;

  for (const entry of KNOWLEDGE_SEED) {
    const existing = await KnowledgeChunk.findOne({ docId: entry.docId }).select('+embedding');

    if (dryRun) {
      console.log(`${existing ? 'UPDATE' : 'CREATE'}  [${entry.language}] ${entry.docId} — ${entry.title}`);
      continue;
    }

    const doc = existing ?? new KnowledgeChunk({ docId: entry.docId });
    const contentChanged = doc.content !== entry.content;

    Object.assign(doc, entry, {
      status: 'approved',
      approvedBy: doctor?._id,
      approvedAt: new Date(),
    });

    // Only spend an embedding call when the text actually changed.
    if (!skipEmbeddings && (contentChanged || !doc.embedding?.length)) {
      try {
        doc.embedding = await embed(`${entry.title}\n${entry.section ?? ''}\n${entry.content}`, {
          taskType: 'RETRIEVAL_DOCUMENT',
          title: entry.title,
        });
        doc.embeddingModel = env.GEMINI_EMBED_MODEL;
        doc.embeddedAt = new Date();
        embedded += 1;
        process.stdout.write('.');
      } catch (err) {
        failed += 1;
        logger.error({ docId: entry.docId, err: err?.message }, 'embedding failed');
      }
    }

    await doc.save();
    if (existing) updated += 1;
    else created += 1;
  }

  if (!dryRun) {
    console.log('');
    logger.info({ created, updated, embedded, failed, total: KNOWLEDGE_SEED.length }, 'knowledge seed complete');

    if (failed > 0) {
      logger.warn(
        'Some chunks have no embedding. They will not be retrievable by vector search ' +
          '(the text-search fallback still finds them). Re-run this script once the API key/quota is sorted.',
      );
    }

    const approved = await KnowledgeChunk.countDocuments({ status: 'approved' });
    const withVectors = await KnowledgeChunk.countDocuments({ embeddedAt: { $ne: null } });
    logger.info({ approved, withVectors }, 'knowledge base state');
  }

  await disconnectDb();
}

main().catch(async (err) => {
  logger.fatal({ err }, 'knowledge seed failed');
  await mongoose.connection.close().catch(() => {});
  process.exit(1);
});

/**
 * Retires patient accounts created during testing.
 *
 * Deactivates rather than deletes. A patient document is referenced by chat
 * messages, food logs, glucose readings, prescriptions and audit entries;
 * removing the user would leave every one of those pointing at nothing, and
 * the audit trail is the part you are least allowed to break. `isActive: false`
 * takes them out of every list the doctor and the dietician see, and is one
 * field to flip back if a name turns out to belong to a real person.
 *
 * Reports by default. Nothing is written without --apply.
 *
 *   node scripts/retireTestPatients.js                       # show what matches
 *   node scripts/retireTestPatients.js --apply               # deactivate them
 *   node scripts/retireTestPatients.js --name "AA Voice Test" --apply
 *   node scripts/retireTestPatients.js --restore --apply     # undo
 */
import mongoose from 'mongoose';
import { env } from '../src/config/env.js';
import { User, ROLES } from '../src/models/User.js';

/// Matched case-insensitively and whole-name only. Deliberately an explicit
/// list rather than a pattern like /test/i: a real patient called "Testa" or a
/// clinic account with "test" in it must not be swept up by a maintenance
/// script run months from now.
const DEFAULT_NAMES = ['AA Voice Test', 'AA Upload Test'];

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const restore = args.includes('--restore');
const nameArgs = args.reduce((acc, a, i) => {
  if (a === '--name' && args[i + 1]) acc.push(args[i + 1]);
  return acc;
}, []);
const names = nameArgs.length ? nameArgs : DEFAULT_NAMES;

async function main() {
  await mongoose.connect(env.MONGODB_URI);

  const matches = await User.find({
    role: ROLES.PATIENT,
    // Anchored, case-insensitive, and escaped — a name is user input, and an
    // unescaped one would let a stray "." match half the patient list.
    name: { $in: names.map((n) => new RegExp(`^${n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i')) },
  })
    .select('name phone isActive createdAt')
    .lean();

  if (matches.length === 0) {
    console.log('No patient matches:', names.join(', '));
    return;
  }

  console.log(`${matches.length} matching account(s):\n`);
  for (const u of matches) {
    console.log(
      `  ${u.name.padEnd(20)} ${String(u.phone).padEnd(16)} ` +
        `${u.isActive === false ? 'already retired' : 'active'}`,
    );
  }

  if (!apply) {
    console.log(`\nNothing written. Re-run with --apply to ${restore ? 'restore' : 'retire'} these.`);
    return;
  }

  const res = await User.updateMany(
    { _id: { $in: matches.map((u) => u._id) } },
    { isActive: restore },
  );
  console.log(`\n${restore ? 'Restored' : 'Retired'} ${res.modifiedCount} account(s).`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exitCode = 1;
  })
  .finally(() => mongoose.disconnect());

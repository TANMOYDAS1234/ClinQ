/**
 * One-off repair: rewrite every stored phone number into E.164.
 *
 * Accounts created before phone normalisation could be saved as bare national
 * digits ("9830000003"). Login looks the number up by exact string match and
 * the app always sends "+919830000003", so such an account cannot be signed
 * into by any input the login screen allows — it is locked out, not merely
 * untidy.
 *
 * Safe to run repeatedly: a number already in E.164 is left untouched, and a
 * number that would collide with an existing account is reported rather than
 * written, so two records can never be merged by accident.
 *
 *   node scripts/normalisePhones.js          # report only
 *   node scripts/normalisePhones.js --apply  # write the changes
 */
import { connectDb } from '../src/config/db.js';
import { User } from '../src/models/User.js';
import { toE164 } from '../src/utils/phone.js';
import { logger } from '../src/config/logger.js';

const apply = process.argv.includes('--apply');

async function main() {
  await connectDb();

  const users = await User.find({}).select('name phone role').lean();
  const changes = [];
  const collisions = [];

  for (const u of users) {
    const fixed = toE164(u.phone);
    if (fixed === u.phone) continue;

    const clash = users.find((o) => String(o._id) !== String(u._id) && o.phone === fixed);
    (clash ? collisions : changes).push({ user: u, fixed, clash });
  }

  if (changes.length === 0 && collisions.length === 0) {
    logger.info('every phone number is already in E.164 — nothing to do');
    return;
  }

  for (const { user, fixed } of changes) {
    logger.info(`${user.role.padEnd(10)} ${user.name}: ${user.phone} -> ${fixed}`);
  }

  for (const { user, fixed, clash } of collisions) {
    logger.warn(
      `SKIPPED ${user.name} (${user.phone} -> ${fixed}): ${clash.name} already holds that number. ` +
        'Decide which account is real and remove the other, then re-run.',
    );
  }

  if (!apply) {
    logger.info(`${changes.length} would be updated. Re-run with --apply to write them.`);
    return;
  }

  for (const { user, fixed } of changes) {
    await User.updateOne({ _id: user._id }, { phone: fixed });
  }
  logger.info(`updated ${changes.length} phone number(s)`);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    logger.error({ err }, 'normalisePhones failed');
    process.exit(1);
  });

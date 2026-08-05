/**
 * Phone numbers are stored in E.164 (`+919830012345`) and looked up by exact
 * string match, so a number written any other way is not a formatting nit — it
 * is an account nobody can sign into.
 *
 * That is exactly what happened: a dietician created with the bare ten digits
 * could never log in, because the login screen sends a fixed `+91` prefix and
 * there is no input that would have matched the stored value.
 *
 * Normalising here rather than trusting each caller means every write and every
 * lookup agrees, whatever the client sent.
 */

/** The clinic is in India; a bare national number is a +91 one. */
const DEFAULT_COUNTRY_CODE = '+91';

/**
 * Returns [raw] in E.164, or the cleaned input unchanged when it is not a form
 * we can safely interpret — never a guess. Validation stays where it was; this
 * only settles the shape.
 */
export function toE164(raw) {
  if (typeof raw !== 'string') return raw;

  const cleaned = raw.trim().replace(/[\s\-()]/g, '');
  if (cleaned.startsWith('+')) return cleaned;

  // 10 digits is an Indian national number.
  if (/^[6-9]\d{9}$/.test(cleaned)) return `${DEFAULT_COUNTRY_CODE}${cleaned}`;

  // "919830012345" — the country code without its plus.
  if (/^91[6-9]\d{9}$/.test(cleaned)) return `+${cleaned}`;

  // "0" trunk prefix, as dialled domestically.
  if (/^0[6-9]\d{9}$/.test(cleaned)) return `${DEFAULT_COUNTRY_CODE}${cleaned.slice(1)}`;

  return cleaned;
}

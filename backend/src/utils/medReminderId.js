/**
 * Deterministic notification id for one dose on one day — identical to the Dart
 * `medReminderNotificationId` on the client, so a server push and the on-device
 * alarm for the same dose collapse into a single notification instead of
 * reminding twice.
 *
 * FNV-1a (32-bit) over `medId|HH:mm|YYYY-MM-DD`, folded into the medication
 * reserved id range [700000, 790000). `Math.imul` keeps the multiply in true
 * 32-bit space so it matches Dart's `(hash * prime) & 0xFFFFFFFF`.
 */
export function medReminderNotificationId(medId, hhmm, dateStr) {
  const key = `${medId}|${hhmm}|${dateStr}`;
  let hash = 0x811c9dc5;
  for (let i = 0; i < key.length; i += 1) {
    hash ^= key.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return 700000 + (hash % 90000);
}

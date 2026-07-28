/**
 * Turns a prescription "frequency" into concrete daily reminder times, so a
 * prescribed or scanned medicine shows up in the patient's schedule — and fires
 * a reminder — without anyone re-entering the times.
 *
 * Handles the Indian "1-0-1" notation (morning-noon-night) and the common
 * shorthands (OD/BD/TDS/QID and their word forms). Times are local clock
 * "HH:mm"; the device schedules the actual alarms.
 */
export function frequencyToTimes(frequency) {
  if (!frequency) return ['08:00'];

  const pattern = String(frequency).replace(/\s/g, '');

  // "1-0-1" / "1-1-1" / "0-0-1" — a slot per non-zero position.
  const tds = /^(\d)-(\d)-(\d)$/.exec(pattern);
  if (tds) {
    const slots = [];
    if (Number(tds[1]) > 0) slots.push('08:00');
    if (Number(tds[2]) > 0) slots.push('14:00');
    if (Number(tds[3]) > 0) slots.push('20:00');
    return slots.length ? slots : ['08:00'];
  }

  // "1-0-1-0" (four-slot) — morning/noon/evening/night.
  const qds = /^(\d)-(\d)-(\d)-(\d)$/.exec(pattern);
  if (qds) {
    const map = ['08:00', '12:00', '16:00', '20:00'];
    const slots = qds.slice(1).map(Number).map((n, i) => (n > 0 ? map[i] : null)).filter(Boolean);
    return slots.length ? slots : ['08:00'];
  }

  const lower = String(frequency).toLowerCase();
  if (/\b(od|once)\b/.test(lower)) return ['08:00'];
  if (/\b(bd|bid|twice)\b/.test(lower)) return ['08:00', '20:00'];
  if (/\b(tds|tid|thrice|three times)\b/.test(lower)) return ['08:00', '14:00', '20:00'];
  if (/\b(qid|qds|four times)\b/.test(lower)) return ['08:00', '12:00', '16:00', '20:00'];
  return ['08:00'];
}

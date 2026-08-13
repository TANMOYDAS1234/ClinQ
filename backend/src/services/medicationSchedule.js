/**
 * Turns a prescription "frequency" into concrete daily reminder times, anchored
 * to the patient's OWN meal times when known — so "before breakfast" fires
 * relative to when they actually eat, not a fixed clock — and shifted by the
 * relation to the meal. Falls back to clinic-standard times when a patient has
 * not set their meal times.
 *
 * Handles the Indian "1-0-1" notation (morning-noon-night) and the common
 * shorthands (OD/BD/TDS/QID and their word forms). Times are local clock
 * "HH:mm"; the device schedules the actual alarms.
 */
import { env } from '../config/env.js';

export const DEFAULT_MEAL_TIMES = Object.freeze({ breakfast: '08:00', lunch: '13:30', dinner: '20:30' });

// Minutes to shift a dose relative to its meal. "before"/"after" are a clinic-
// wide convention set in config (default ∓30); with-meal and any never shift.
const MEAL_OFFSET_MIN = {
  before_meal: -env.MEAL_OFFSET_BEFORE_MIN,
  after_meal: env.MEAL_OFFSET_AFTER_MIN,
  with_meal: 0,
  any: 0,
};

function addMinutes(hhmm, delta) {
  const [h, m] = String(hhmm).split(':').map(Number);
  const total = (((h * 60 + m + delta) % 1440) + 1440) % 1440;
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}

/** Which meal each dose slot hangs off. */
function slotBase(slot, meals) {
  switch (slot) {
    case 'morning':
      return meals.breakfast;
    case 'noon':
      return meals.lunch;
    case 'afternoon':
      return addMinutes(meals.lunch, 180);
    case 'night':
      return meals.dinner;
    case 'bedtime':
      // ~90 min after dinner — HS ("hora somni", at bedtime).
      return addMinutes(meals.dinner, 90);
    default:
      return meals.breakfast;
  }
}

/** The clock time for a dose slot, given the patient's meals and meal relation. */
export function slotToTime(slot, mealTimes, relationToMeal = 'any') {
  const meals = { ...DEFAULT_MEAL_TIMES, ...(mealTimes ?? {}) };
  return addMinutes(slotBase(slot, meals), MEAL_OFFSET_MIN[relationToMeal] ?? 0);
}

/** Frequency notation → the ordered dose slots it means. */
export function frequencyToSlots(frequency) {
  if (!frequency) return ['morning'];

  const pattern = String(frequency).replace(/\s/g, '');

  const tds = /^(\d)-(\d)-(\d)$/.exec(pattern);
  if (tds) {
    const slots = [];
    if (Number(tds[1]) > 0) slots.push('morning');
    if (Number(tds[2]) > 0) slots.push('noon');
    if (Number(tds[3]) > 0) slots.push('night');
    return slots.length ? slots : ['morning'];
  }

  const qds = /^(\d)-(\d)-(\d)-(\d)$/.exec(pattern);
  if (qds) {
    const map = ['morning', 'noon', 'afternoon', 'night'];
    const slots = qds.slice(1).map(Number).map((n, i) => (n > 0 ? map[i] : null)).filter(Boolean);
    return slots.length ? slots : ['morning'];
  }

  const lower = String(frequency).toLowerCase();
  // As-needed / immediate one-off carry no recurring schedule at all.
  if (/\b(prn|sos|stat)\b/.test(lower)) return [];
  if (/\b(hs|bedtime|nocte|on)\b/.test(lower)) return ['bedtime'];
  if (/\b(od|qd|once|om)\b/.test(lower)) return ['morning'];
  if (/\b(bd|bid|twice)\b/.test(lower)) return ['morning', 'night'];
  if (/\b(tds|tid|thrice|three times)\b/.test(lower)) return ['morning', 'noon', 'night'];
  if (/\b(qid|qds|four times)\b/.test(lower)) return ['morning', 'noon', 'afternoon', 'night'];
  return ['morning'];
}

/** Backward-compatible: frequency → concrete times (meal-aware if opts given). */
export function frequencyToTimes(frequency, { mealTimes, relationToMeal = 'any' } = {}) {
  return frequencyToSlots(frequency).map((slot) => slotToTime(slot, mealTimes, relationToMeal));
}

/**
 * Full schedule entries for a prescription item — keeps the `slot` so the times
 * can be re-derived later if the patient changes their meal times.
 */
export function buildSchedule(frequency, mealTimes, relationToMeal = 'any') {
  return frequencyToSlots(frequency).map((slot) => ({
    slot,
    time: slotToTime(slot, mealTimes, relationToMeal),
    relationToMeal,
  }));
}

/** Re-derive times for existing schedule entries against new meal times. */
export function recomputeSchedule(schedule, mealTimes) {
  return (schedule ?? []).map((s) => ({
    slot: s.slot ?? null,
    relationToMeal: s.relationToMeal ?? 'any',
    // Only slot-anchored entries can move; a manually-set time with no slot stays.
    time: s.slot ? slotToTime(s.slot, mealTimes, s.relationToMeal ?? 'any') : s.time,
  }));
}

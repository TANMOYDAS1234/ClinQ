import { test } from 'node:test';
import assert from 'node:assert/strict';

import { env } from '../src/config/env.js';
import { slotToTime, buildSchedule, recomputeSchedule } from '../src/services/medicationSchedule.js';

// The patient's own meal times; "before/after food" must anchor to these.
const meals = { breakfast: '08:00', lunch: '13:00', dinner: '21:00' };

test('meal-relative dose timing', async (t) => {
  await t.test('before food shifts earlier by the configured offset', () => {
    const shifted = slotToTime('morning', meals, 'before_meal');
    // 08:00 minus MEAL_OFFSET_BEFORE_MIN.
    const [h, m] = shifted.split(':').map(Number);
    assert.equal(h * 60 + m, 8 * 60 - env.MEAL_OFFSET_BEFORE_MIN);
  });

  await t.test('after food shifts later by the configured offset', () => {
    const shifted = slotToTime('night', meals, 'after_meal');
    const [h, m] = shifted.split(':').map(Number);
    assert.equal(h * 60 + m, 21 * 60 + env.MEAL_OFFSET_AFTER_MIN);
  });

  await t.test('with food and any never shift', () => {
    assert.equal(slotToTime('noon', meals, 'with_meal'), '13:00');
    assert.equal(slotToTime('noon', meals, 'any'), '13:00');
  });

  await t.test('a slot-anchored schedule re-derives when meal times move', () => {
    const built = buildSchedule('1-0-1', meals, 'before_meal');
    // Breakfast moves an hour later → the morning reminder moves with it.
    const moved = recomputeSchedule(built, { ...meals, breakfast: '09:00' });
    const morning = moved.find((s) => s.slot === 'morning');
    const [h, m] = morning.time.split(':').map(Number);
    assert.equal(h * 60 + m, 9 * 60 - env.MEAL_OFFSET_BEFORE_MIN);
  });

  await t.test('a hand-set time with no slot stays put when meals move', () => {
    const manual = [{ time: '06:15', relationToMeal: 'any' }];
    assert.equal(recomputeSchedule(manual, { ...meals, breakfast: '09:00' })[0].time, '06:15');
  });
});

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { windowsForDate, buildSlotTimes } from '../src/services/scheduling.js';
import { clinicDayOfWeek } from '../src/utils/clinicTime.js';

// A concrete clinic-local calendar date; its day-of-week is derived so the
// tests hold regardless of which weekday it actually falls on.
const DATE = '2026-07-27';
const DOW = clinicDayOfWeek(DATE);
const OTHER_DOW = (DOW + 1) % 7;

const clinic = (over = {}) => ({
  slotMinutes: 15,
  weeklyHours: [{ dayOfWeek: DOW, start: '10:00', end: '11:00' }],
  overrides: [],
  ...over,
});

test('scheduling: slot times', async (t) => {
  await t.test('weekly window yields slot starts up to but not including the end', () => {
    assert.deepEqual(
      buildSlotTimes(clinic(), DATE).map((s) => s.time),
      ['10:00', '10:15', '10:30', '10:45'],
    );
  });

  await t.test('a different weekday produces no slots', () => {
    const c = clinic({ weeklyHours: [{ dayOfWeek: OTHER_DOW, start: '10:00', end: '11:00' }] });
    assert.equal(buildSlotTimes(c, DATE).length, 0);
  });

  await t.test('slotMinutes controls the step', () => {
    const c = clinic({ slotMinutes: 20, weeklyHours: [{ dayOfWeek: DOW, start: '18:00', end: '19:00' }] });
    assert.deepEqual(buildSlotTimes(c, DATE).map((s) => s.time), ['18:00', '18:20', '18:40']);
  });

  await t.test('two windows on the same day merge and sort', () => {
    const c = clinic({
      weeklyHours: [
        { dayOfWeek: DOW, start: '17:00', end: '17:30' },
        { dayOfWeek: DOW, start: '10:00', end: '10:30' },
      ],
    });
    assert.deepEqual(buildSlotTimes(c, DATE).map((s) => s.time), ['10:00', '10:15', '17:00', '17:15']);
  });
});

test('scheduling: overrides win over the weekly pattern', async (t) => {
  await t.test('a closure clears the day', () => {
    const c = clinic({ overrides: [{ date: DATE, isClosed: true, windows: [] }] });
    assert.deepEqual(windowsForDate(c, DATE), []);
    assert.equal(buildSlotTimes(c, DATE).length, 0);
  });

  await t.test('special hours replace the weekly ones', () => {
    const c = clinic({ overrides: [{ date: DATE, isClosed: false, windows: [{ start: '18:00', end: '18:30' }] }] });
    assert.deepEqual(buildSlotTimes(c, DATE).map((s) => s.time), ['18:00', '18:15']);
  });

  await t.test('an empty non-closing override falls through to the weekly pattern', () => {
    const c = clinic({ overrides: [{ date: DATE, isClosed: false, windows: [] }] });
    assert.deepEqual(buildSlotTimes(c, DATE).map((s) => s.time), ['10:00', '10:15', '10:30', '10:45']);
  });
});

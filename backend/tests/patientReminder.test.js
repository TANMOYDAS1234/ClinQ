import { test } from 'node:test';
import assert from 'node:assert/strict';

import { shouldNudgeGlucose } from '../src/services/patientReminderCron.js';

test('glucose check-in back-off', async (t) => {
  await t.test('never nudges someone who already logged today', () => {
    assert.equal(shouldNudgeGlucose(0), false);
    assert.equal(shouldNudgeGlucose(-1), false);
  });

  await t.test('daily for the first three lapsed days', () => {
    assert.equal(shouldNudgeGlucose(1), true);
    assert.equal(shouldNudgeGlucose(2), true);
    assert.equal(shouldNudgeGlucose(3), true);
  });

  await t.test('every other day from day four through a fortnight', () => {
    assert.equal(shouldNudgeGlucose(4), false);
    assert.equal(shouldNudgeGlucose(5), true);
    assert.equal(shouldNudgeGlucose(6), false);
    assert.equal(shouldNudgeGlucose(7), true);
    assert.equal(shouldNudgeGlucose(13), true);
    assert.equal(shouldNudgeGlucose(14), false);
  });

  await t.test('weekly only once a patient is long lapsed', () => {
    assert.equal(shouldNudgeGlucose(15), false);
    assert.equal(shouldNudgeGlucose(21), true);
    assert.equal(shouldNudgeGlucose(28), true);
    assert.equal(shouldNudgeGlucose(30), false);
  });
});

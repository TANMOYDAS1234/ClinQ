import { describe, test } from 'node:test';
import assert from 'node:assert/strict';

import { KNOWLEDGE_SEED } from '../src/knowledge/seedContent.js';

/**
 * The corpus is what the assistant is allowed to answer from, so its shape is
 * worth asserting: a domain missing here is a question the assistant must
 * refuse.
 */
describe('knowledge base coverage', () => {
  const categories = new Set(KNOWLEDGE_SEED.map((c) => c.category));

  test('covers every primary clinical domain the clinic treats', () => {
    for (const c of [
      'hypoglycaemia', 'hyperglycaemia', 'insulin', 'thyroid', 'hypertension',
      'dyslipidaemia', 'obesity_metabolic', 'pcos', 'adrenal', 'pituitary',
      'bone_metabolism', 'gout',
    ]) {
      assert.ok(categories.has(c), `no approved content for: ${c}`);
    }
  });

  test('covers complications patients ask about constantly', () => {
    for (const c of ['kidney', 'eye_care', 'neuropathy', 'foot_care', 'cardiovascular', 'liver']) {
      assert.ok(categories.has(c), `no approved content for: ${c}`);
    }
  });

  test('covers the supporting knowledge', () => {
    for (const c of [
      'pharmacology', 'lab_interpretation', 'devices', 'diet', 'exercise',
      'preventive_care', 'special_populations', 'mental_health', 'sexual_health',
      'sick_day_rules',
    ]) {
      assert.ok(categories.has(c), `no approved content for: ${c}`);
    }
  });

  test('every chunk is complete enough to cite', () => {
    for (const c of KNOWLEDGE_SEED) {
      for (const field of ['docId', 'title', 'category', 'language', 'content', 'sourceCitation']) {
        assert.ok(c[field], `${c.docId ?? '?'} is missing ${field}`);
      }
      assert.ok(['en', 'bn', 'hi'].includes(c.language), `${c.docId}: bad language`);
      assert.ok(c.content.length > 200, `${c.docId}: content too thin to be useful`);
    }
  });

  test('docIds are unique — a duplicate would silently overwrite on seed', () => {
    const ids = KNOWLEDGE_SEED.map((c) => c.docId);
    assert.equal(new Set(ids).size, ids.length);
  });

  test('the safety-critical topics exist in all three languages', () => {
    // A patient reading in Bengali must not be left without hypoglycaemia or
    // foot-care guidance in their own language.
    for (const category of ['hypoglycaemia', 'foot_care']) {
      for (const language of ['en', 'bn', 'hi']) {
        assert.ok(
          KNOWLEDGE_SEED.some((c) => c.category === category && c.language === language),
          `${category} has no ${language} content`,
        );
      }
    }
  });
});

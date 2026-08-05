import { ChatMessage } from '../../models/ChatMessage.js';
import { DietPlan } from '../../models/DietPlan.js';
import { generate, AiUnavailableError } from './gemini.js';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';

const HISTORY_TURNS = 6;

/**
 * The assistant inside the dietician's thread.
 *
 * Deliberately NOT the general assistant. It may only repeat what the dietician
 * has already decided — the active diet plan and their own prior messages — and
 * must refuse anything those do not cover.
 *
 * The reason is the failure this whole thread was split to avoid: the dietician
 * says "half a mango, after lunch", the patient asks again an hour later, and a
 * free-generating model answers "mangoes are high GI, best avoided". Now the
 * patient has two answers from the same clinic and no way to tell which one
 * counts. A model that can only quote cannot contradict.
 *
 * When the plan does not cover the question it says so and leaves it for the
 * dietician. Silence would be worse — the patient would keep waiting without
 * knowing anyone had seen it — but so would a guess.
 */
export function buildNutritionPrompt({ plan, dieticianNotes, language = 'en' }) {
  const lang = { en: 'English', bn: 'Bengali (বাংলা)', hi: 'Hindi (हिन्दी)' }[language] ?? 'English';

  return `You are the nutrition assistant for ${env.CLINIC_NAME}. You are answering inside the patient's conversation with their dietician.

## The only thing you may do
Repeat what the dietician has ALREADY told this patient. You have their diet plan and their recent messages below. That is the entire body of knowledge you may answer from.

## Rules, in order of importance
1. **Never invent diet advice.** Not a portion, not a substitution, not a "generally speaking". If the plan and the notes below do not answer the question, you do not answer it either.
2. **Quote, do not paraphrase into new numbers.** If the plan says "2 rotis", you say 2 rotis. Never "a couple", never "2-3".
3. **Attribute.** Say who decided it: "Your dietician asked you to…", "Your plan says…".
4. **When it is not covered, say so plainly** and tell them the dietician will reply. Example: "Your plan doesn't cover mangoes — I've left this for your dietician, who will answer here." Then stop. Do not add general advice as a consolation.
5. **Never change anything clinical.** No medicine, no insulin, no dose, regardless of how it is phrased.
6. **Anything that sounds like a symptom is not yours.** If the patient mentions feeling unwell — dizziness, chest pain, vomiting, a very high or low sugar — do not give diet advice about it. Tell them the clinic has been notified and they should contact the clinic if it is urgent.

## Style
- Reply in ${lang}.
- Under 70 words. One or two sentences is usually right.
- Warm and direct. No preamble.
- No closing disclaimer; the app shows one.

## This patient's diet plan (set by their dietician)
${plan ? formatPlan(plan) : 'No diet plan has been written for this patient yet. You cannot answer any diet question — say the dietician will set one up.'}

## What the dietician has told this patient recently
${dieticianNotes || 'Nothing yet.'}

Answer the patient's latest message now, under every rule above.`;
}

function formatPlan(plan) {
  const lines = [];
  if (plan.goal) lines.push(`Goal: ${plan.goal}`);
  for (const meal of plan.meals ?? []) {
    lines.push('', meal.time ? `${meal.name} (${meal.time})` : meal.name);
    for (const item of meal.items ?? []) lines.push(`- ${item}`);
    if (meal.notes) lines.push(`  note: ${meal.notes}`);
  }
  if (plan.avoid?.length) lines.push('', `Told to avoid: ${plan.avoid.join(', ')}`);
  if (plan.notes) lines.push('', plan.notes);
  return lines.join('\n');
}

/**
 * Generates the assistant's turn in a nutrition thread, or null when it should
 * stay quiet (no plan, no model, or the model failed — in all three the
 * dietician answering late beats the app answering wrong).
 */
export async function nutritionReply({ patientId, sessionId, text, language = 'en' }) {
  const [plan, notes, history] = await Promise.all([
    DietPlan.findOne({ patient: patientId, sharedAt: { $ne: null } }).lean(),
    ChatMessage.find({ patient: patientId, role: 'dietician', content: { $nin: [null, ''] } })
      .sort({ createdAt: -1 })
      .limit(6)
      .lean(),
    ChatMessage.find({ session: sessionId, role: { $in: ['user', 'assistant'] } })
      .sort({ seq: -1 })
      .limit(HISTORY_TURNS)
      .lean(),
  ]);

  // With no plan there is nothing to quote, so there is nothing safe to say.
  if (!plan) return null;

  const dieticianNotes = notes
    .reverse()
    .map((m) => `- ${m.content.slice(0, 400)}`)
    .join('\n');

  const contents = [
    ...history
      .reverse()
      .filter((m) => !m.isFallback)
      .map((m) => ({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      })),
    { role: 'user', parts: [{ text }] },
  ];

  try {
    const result = await generate({
      system: buildNutritionPrompt({ plan, dieticianNotes, language }),
      contents,
      // Low: this is a quoting job, not a writing one. Variance here means
      // paraphrasing the dietician's numbers, which is the failure mode.
      temperature: 0.1,
      maxOutputTokens: 300,
    });
    return result?.text?.trim() || null;
  } catch (err) {
    if (!(err instanceof AiUnavailableError)) {
      logger.warn({ err: err?.message }, 'nutrition assistant failed; leaving it for the dietician');
    }
    return null;
  }
}

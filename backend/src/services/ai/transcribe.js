import { generate } from './gemini.js';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';

/**
 * Turns a patient's voice note into text the rest of the pipeline can use.
 *
 * This runs *before* triage, and that ordering is the point: the deterministic
 * rule engine reads text, so a patient who says "I have chest pain" out loud
 * must reach the same escalation as one who typed it. Transcribing server-side
 * rather than on the handset is what makes that true regardless of whether the
 * phone has a speech recogniser, or one that speaks Bengali.
 */
const SYSTEM = `You transcribe voice messages from patients of a diabetes and hormone clinic in India.

Rules:
- Return ONLY the words spoken. No summary, no commentary, no speaker labels.
- Transcribe in the language actually spoken — English, Bengali or Hindi. Do not translate.
- Keep numbers as digits: "two forty" spoken about a sugar reading becomes "240".
- Keep medicine names as spoken, even if unfamiliar.
- If the audio is silent or unintelligible, return exactly: [unclear]`;

/**
 * @param {Buffer} buffer raw audio bytes as uploaded
 * @param {string} mimeType the recording's content type
 * @returns {Promise<string|null>} spoken words, or null when nothing usable
 */
export async function transcribeVoiceNote(buffer, mimeType) {
  try {
    const result = await generate({
      system: SYSTEM,
      contents: [
        {
          role: 'user',
          parts: [
            { text: 'Transcribe this voice message.' },
            { inlineData: { mimeType, data: buffer.toString('base64') } },
          ],
        },
      ],
      model: env.GEMINI_VISION_MODEL,
      // Transcription is not a creative task; drift here invents symptoms.
      temperature: 0,
    });

    const text = (result?.text ?? '').trim();
    if (!text || text === '[unclear]') return null;
    return text;
  } catch (err) {
    // Never fatal. A failed transcription costs the assistant its answer, but
    // the recording is already stored and the clinic can still listen to it —
    // losing the message entirely would be far worse.
    logger.error({ err }, 'voice note transcription failed');
    return null;
  }
}

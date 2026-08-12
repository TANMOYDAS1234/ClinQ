import { MediaAsset } from '../models/MediaAsset.js';

/**
 * A voice note arrives as an attachment whose spoken words were transcribed at
 * upload. When the patient sends ONLY audio (no typed text), the assistants and
 * triage would otherwise be handed an empty string and answer nothing useful —
 * so substitute the transcript as the message text.
 *
 * Returns the original text when it is non-empty, otherwise the first non-empty
 * transcript among the voice-note attachments, otherwise the original text.
 */
export async function resolveVoiceText(text, attachments = []) {
  if (text && text.trim()) return text;
  if (!attachments || attachments.length === 0) return text ?? '';

  const assets = await MediaAsset.find({ _id: { $in: attachments }, kind: 'voice_note' })
    .select('transcript')
    .lean();
  const transcript = assets.map((a) => a.transcript).find((s) => s && s.trim());
  return transcript ? transcript.trim() : (text ?? '');
}

import { ChatSession } from '../../models/ChatSession.js';
import { ChatMessage } from '../../models/ChatMessage.js';
import { triageMessage } from '../triage/engine.js';
import { buildPatientContext } from '../patientContext.js';
import { retrieve, formatContext } from './rag.js';
import { generate, AiUnavailableError } from './gemini.js';
import { buildSystemPrompt, fallbackReply } from './prompts.js';
import { raiseAlert } from '../alerts.js';
import { loadAssetsForAi } from '../../routes/uploads.js';
import { logger } from '../../config/logger.js';
import { maxUrgency } from '../triage/thresholds.js';
import { env } from '../../config/env.js';

const HISTORY_TURNS = 8;

/**
 * Defensively strip a disclaimer the model may still append despite the prompt
 * telling it not to. The app owns the single footer disclaimer; anything the
 * model adds is a duplicate. Matches a trailing line that opens with an em- or
 * en-dash and mentions "AI" guidance, in any of the three languages.
 */
function stripTrailingDisclaimer(text) {
  return text
    .replace(/\n+\s*[—–-]\s*(This is |এটি|यह)[\s\S]*$/u, '')
    .trim();
}

/** Maps triage findings to the knowledge categories worth retrieving. */
function categoriesFor(triage) {
  const cats = new Set();
  for (const rule of triage.matchedRules) {
    if (rule.startsWith('GL_SEVERE_HYPO') || rule === 'GL_HYPO') cats.add('hypoglycaemia');
    if (rule.startsWith('GL_CRITICAL') || rule === 'GL_VERY_HIGH') cats.add('hyperglycaemia');
    if (rule.startsWith('RF_FOOT')) cats.add('foot_care');
    if (rule.startsWith('RF_VISION')) cats.add('eye_care');
    if (rule.startsWith('BP_')) cats.add('hypertension');
    if (rule === 'RF_MISSED_INSULIN') cats.add('insulin');
    if (rule === 'RF_DKA') cats.add('sick_day_rules');
    if (rule === 'RF_CHEST_PAIN' || rule === 'RF_BREATHING' || rule === 'RF_STROKE') cats.add('emergency');
  }
  return [...cats];
}

/**
 * Handles one patient turn end to end.
 *
 * Order is deliberate and load-bearing:
 *   1. persist the patient's message (never lose it, even if everything else fails)
 *   2. triage deterministically
 *   3. escalate immediately if it is an emergency — before any model call, so a
 *      Gemini outage cannot delay the clinic being paged
 *   4. retrieve grounding, then generate
 *   5. fall back to a written emergency script if generation fails
 */
export async function handlePatientMessage({ patientId, sessionId, text, language = 'en', attachments = [] }) {
  const session = await resolveSession({ patientId, sessionId, language, text });

  const context = await buildPatientContext(patientId);

  const triage = triageMessage({
    text,
    targets: context.targets,
    latestGlucose: context.latestGlucose,
  });

  const seq = session.messageCount + 1;
  const userMessage = await ChatMessage.create({
    session: session._id,
    patient: patientId,
    seq,
    role: 'user',
    content: text,
    language,
    attachments,
    triage: {
      urgency: triage.urgency,
      matchedRules: triage.matchedRules,
      redFlags: triage.redFlags.map((r) => r.label),
      ruleDriven: triage.ruleDriven,
    },
  });

  // Escalate before generating. The clinic learns about a chest-pain message
  // whether or not the model ever responds.
  let alert = null;
  if (triage.urgency === 'emergency' || triage.urgency === 'urgent') {
    alert = await raiseAlert({
      patientId,
      severity: triage.urgency === 'emergency' ? 'emergency' : 'urgent',
      type: triage.alertType ?? 'chat_escalation',
      title: triage.redFlags[0]?.label ?? triage.findings[0]?.summary ?? 'Patient reported a concerning symptom',
      detail: `Patient message: "${text.slice(0, 500)}"\n\nTriage findings:\n${triage.findings.map((f) => `- ${f.summary}`).join('\n')}`,
      source: { kind: 'chat', ref: userMessage._id },
      matchedRules: triage.matchedRules,
    });
    await ChatMessage.findByIdAndUpdate(userMessage._id, { alert: alert._id });
  }

  // Retrieve grounding + prior turns in parallel.
  const [chunks, history] = await Promise.all([
    retrieve(text, { language, categories: categoriesFor(triage), limit: 6 }).catch((err) => {
      logger.warn({ err: err?.message }, 'retrieval failed; answering without grounding');
      return [];
    }),
    ChatMessage.find({ session: session._id, seq: { $lt: seq } })
      .sort({ seq: -1 })
      .limit(HISTORY_TURNS)
      .lean(),
  ]);

  // If the patient attached photos, load them so the assistant can actually
  // look at them. Without this the image is stored but never seen, and the
  // reply is "I can't tell without knowing what you ate" — which reads as the
  // photo being ignored.
  const images = attachments.length ? await loadAssetsForAi(attachments).catch(() => []) : [];
  const userParts = [{ text }, ...images.map((img) => ({ inlineData: { mimeType: img.mimeType, data: img.base64 } }))];

  const contents = [
    ...history
      .reverse()
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] })),
    { role: 'user', parts: userParts },
  ];

  const system = buildSystemPrompt({
    language,
    triage,
    patientContext: context.text,
    groundingContext: formatContext(chunks),
  });

  let replyText;
  let isFallback = false;
  let modelVersion = null;
  let latencyMs = null;
  let usage = {};

  try {
    const result = await generate({
      system,
      contents,
      temperature: triage.urgency === 'emergency' ? 0.1 : 0.3,
      // Shorter cap: patient replies should be tight, and a smaller ceiling
      // discourages the model from padding.
      maxOutputTokens: 600,
      // Use the vision model when there are images so it can read them.
      model: images.length ? env.GEMINI_VISION_MODEL : undefined,
    });
    replyText = stripTrailingDisclaimer(result.text.trim());
    modelVersion = result.modelVersion;
    latencyMs = result.latencyMs;
    usage = result.usage;
  } catch (err) {
    if (!(err instanceof AiUnavailableError)) throw err;
    logger.error({ err: err.cause?.message }, 'assistant generation failed; using scripted fallback');
    // In an emergency the scripted emergency text is what matters, not an
    // apology about the service being down.
    replyText = fallbackReply(triage.urgency === 'emergency' ? 'emergency' : 'unavailable', language);
    isFallback = true;
  }

  // No disclaimer is appended to the content: the app already renders one
  // footer line under every assistant reply, and appending here produced a
  // duplicate (sometimes triple, when the model added its own too).
  const assistantMessage = await ChatMessage.create({
    session: session._id,
    patient: patientId,
    seq: seq + 1,
    role: 'assistant',
    content: replyText,
    language,
    triage: {
      urgency: triage.urgency,
      matchedRules: triage.matchedRules,
      redFlags: triage.redFlags.map((r) => r.label),
      ruleDriven: triage.ruleDriven,
    },
    // Cap at 3: six full-width source chips buried the answer off-screen.
    // Retrieval still uses the full set for grounding; this only trims what
    // the patient sees.
    citations: chunks.slice(0, 3).map((c) => ({ chunk: c._id, title: c.title, score: c.score })),
    modelVersion,
    latencyMs,
    tokenUsage: usage,
    isFallback,
    alert: alert?._id,
  });

  session.messageCount = seq + 1;
  session.lastMessageAt = new Date();
  session.highestUrgency = maxUrgency(session.highestUrgency, triage.urgency);
  if (triage.urgency === 'emergency' || triage.urgency === 'urgent') session.flaggedForReview = true;
  await session.save();

  return {
    sessionId: session._id,
    userMessage: serialiseMessage(userMessage),
    reply: serialiseMessage(assistantMessage),
    triage: {
      urgency: triage.urgency,
      ruleDriven: triage.ruleDriven,
      redFlags: triage.redFlags,
      findings: triage.findings.map((f) => f.summary),
      extracted: triage.extracted,
    },
    alert: alert
      ? { id: alert._id, severity: alert.severity, type: alert.type, title: alert.title }
      : null,
    citations: chunks.slice(0, 3).map((c) => ({ id: c._id, title: c.title, source: c.sourceCitation ?? null })),
  };
}

async function resolveSession({ patientId, sessionId, language, text }) {
  if (sessionId) {
    const existing = await ChatSession.findOne({ _id: sessionId, patient: patientId });
    if (existing) return existing;
  }
  return ChatSession.create({
    patient: patientId,
    language,
    // First message doubles as the thread title; trimmed to fit a list row.
    title: text.length > 60 ? `${text.slice(0, 57)}...` : text,
  });
}

function serialiseMessage(m) {
  return {
    id: m._id,
    seq: m.seq,
    role: m.role,
    content: m.content,
    language: m.language,
    urgency: m.triage?.urgency ?? 'routine',
    isFallback: m.isFallback ?? false,
    createdAt: m.createdAt,
  };
}

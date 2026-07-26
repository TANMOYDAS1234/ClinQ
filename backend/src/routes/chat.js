import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { requireAuth, requireClinician, resolvePatientScope } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound } from '../middleware/errors.js';
import { audit } from '../middleware/audit.js';
import { handlePatientMessage, streamPatientMessage } from '../services/ai/assistant.js';
import { ChatSession } from '../models/ChatSession.js';
import { ChatMessage } from '../models/ChatMessage.js';
import { notifyPatientOfClinicianReply } from '../services/notifications.js';
import { paged, pageParams } from '../utils/pagination.js';

const router = Router();

/**
 * Generation is the expensive path. The limit is generous enough that an
 * anxious patient in a genuine crisis is never locked out, but low enough to
 * stop a runaway client from burning the API quota.
 */
const chatLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 20,
  keyGenerator: (req) => req.user?._id?.toString() ?? req.ip,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: {
    error: {
      code: 'RATE_LIMITED',
      message: 'You are sending messages very quickly. Please wait a moment. If this is an emergency, go to the nearest hospital.',
    },
  },
});

router.post(
  '/message',
  requireAuth,
  chatLimiter,
  validate({
    body: z.object({
      sessionId: z.string().optional(),
      text: z.string().trim().min(1, 'Message cannot be empty').max(4000),
      language: z.enum(['en', 'bn', 'hi']).optional(),
      attachments: z.array(z.string()).max(5).default([]),
    }),
  }),
  audit('create', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const result = await handlePatientMessage({
      patientId: req.user._id,
      sessionId: req.body.sessionId,
      text: req.body.text,
      language: req.body.language ?? req.user.language ?? 'en',
      attachments: req.body.attachments,
    });
    res.json(result);
  }),
);

/**
 * Streaming sibling of POST /message. Same triage-first safety order, but the
 * reply is delivered as Server-Sent Events so the app can show words as they
 * are generated. The client falls back to the non-streaming endpoint if the
 * stream cannot be opened.
 */
router.post(
  '/message/stream',
  requireAuth,
  chatLimiter,
  validate({
    body: z.object({
      sessionId: z.string().optional(),
      text: z.string().trim().min(1, 'Message cannot be empty').max(4000),
      language: z.enum(['en', 'bn', 'hi']).optional(),
      attachments: z.array(z.string()).max(5).default([]),
    }),
  }),
  audit('create', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    res.set({
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      // Stop nginx from buffering the stream so tokens arrive as they are sent.
      'X-Accel-Buffering': 'no',
    });
    res.flushHeaders();

    const send = (type, data) => res.write(`event: ${type}\ndata: ${JSON.stringify(data)}\n\n`);

    try {
      for await (const ev of streamPatientMessage({
        patientId: req.user._id,
        sessionId: req.body.sessionId,
        text: req.body.text,
        language: req.body.language ?? req.user.language ?? 'en',
        attachments: req.body.attachments,
      })) {
        send(ev.type, ev.data);
      }
    } catch (err) {
      // The generator already scripts a fallback for AI failures; this catches
      // anything earlier (DB, retrieval) so the client is not left hanging.
      send('error', { message: 'Something went wrong. Please try again.' });
    } finally {
      res.end();
    }
  }),
);

router.get(
  '/sessions',
  requireAuth,
  validate({ query: pageParams }),
  asyncHandler(async (req, res) => {
    const { page, limit, skip } = q(req);
    const filter = { patient: req.user._id, isArchived: false };
    const [items, total] = await Promise.all([
      ChatSession.find(filter).sort({ lastMessageAt: -1 }).skip(skip).limit(limit).lean(),
      ChatSession.countDocuments(filter),
    ]);
    res.json(paged(items.map(serialiseSession), { page, limit, total }));
  }),
);

router.get(
  '/sessions/:id/messages',
  requireAuth,
  validate({ query: pageParams }),
  audit('read', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const session = await ChatSession.findOne({ _id: req.params.id, patient: req.user._id });
    if (!session) throw notFound('Conversation not found');

    const { page, limit, skip } = q(req);
    const filter = { session: session._id };
    const [items, total] = await Promise.all([
      ChatMessage.find(filter).sort({ seq: 1 }).skip(skip).limit(limit).populate('sender', 'name').lean(),
      ChatMessage.countDocuments(filter),
    ]);

    res.json({
      ...paged(items.map(serialiseMessage), { page, limit, total }),
      session: serialiseSession(session.toObject()),
    });
  }),
);

router.post(
  '/sessions/:id/archive',
  requireAuth,
  asyncHandler(async (req, res) => {
    const updated = await ChatSession.findOneAndUpdate(
      { _id: req.params.id, patient: req.user._id },
      { isArchived: true },
    );
    if (!updated) throw notFound('Conversation not found');
    res.status(204).end();
  }),
);

router.post(
  '/messages/:id/flag',
  requireAuth,
  asyncHandler(async (req, res) => {
    const message = await ChatMessage.findOneAndUpdate(
      { _id: req.params.id, patient: req.user._id },
      { flaggedByPatient: true },
    );
    if (!message) throw notFound('Message not found');
    // A patient reporting a bad answer is a review signal for the doctor.
    await ChatSession.updateOne({ _id: message.session }, { flaggedForReview: true });
    res.status(204).end();
  }),
);

/**
 * The doctor (or staff) speaking directly into the patient's assistant thread.
 *
 * There is deliberately no separate doctor-patient inbox. The assistant handles
 * what it safely can and refers the rest to the clinic; a reply that arrived in
 * a different screen would split one clinical conversation in two, and neither
 * half would carry the context of the other. So a clinician's words land in the
 * same thread the patient is already reading, as `role: 'clinician'` — a role
 * the message schema has always allowed.
 *
 * It attaches to the patient's most recent session, or opens one if the patient
 * has never written, so the clinic can always reach out first.
 */
router.post(
  '/patients/:patientId/clinician-message',
  requireAuth,
  requireClinician,
  resolvePatientScope,
  validate({ body: z.object({ content: z.string().trim().min(1).max(4000) }) }),
  audit('create', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    let session = await ChatSession.findOne({ patient: req.patientId, isArchived: false }).sort({
      lastMessageAt: -1,
    });

    if (!session) {
      session = await ChatSession.create({
        patient: req.patientId,
        language: req.patientUser?.language ?? 'en',
        title: 'Message from the clinic',
      });
    }

    // seq is unique per session, so derive it from the current tail rather than
    // a count — an archived or partially deleted history would collide.
    const last = await ChatMessage.findOne({ session: session._id }).sort({ seq: -1 }).select('seq').lean();

    const message = await ChatMessage.create({
      session: session._id,
      patient: req.patientId,
      seq: (last?.seq ?? -1) + 1,
      role: 'clinician',
      sender: req.user._id,
      content: req.body.content,
      language: session.language,
    });

    await ChatSession.findByIdAndUpdate(session._id, {
      lastMessageAt: message.createdAt,
      $inc: { messageCount: 1 },
      // The clinician has now answered, so it no longer needs review.
      flaggedForReview: false,
    });

    await notifyPatientOfClinicianReply(req.patientId, req.user, req.body.content);

    res.status(201).json({
      sessionId: session._id,
      message: { ...serialiseMessage(message), senderName: req.user.name },
    });
  }),
);

function serialiseSession(s) {
  return {
    id: s._id,
    title: s.title,
    language: s.language,
    messageCount: s.messageCount,
    highestUrgency: s.highestUrgency,
    lastMessageAt: s.lastMessageAt,
    flaggedForReview: s.flaggedForReview,
    createdAt: s.createdAt,
  };
}

function serialiseMessage(m) {
  return {
    id: m._id,
    seq: m.seq,
    role: m.role,
    // Present on clinician turns once populated; null everywhere else.
    senderName: m.sender && typeof m.sender === 'object' ? (m.sender.name ?? null) : null,
    content: m.content,
    language: m.language,
    urgency: m.triage?.urgency ?? 'routine',
    redFlags: m.triage?.redFlags ?? [],
    citations: (m.citations ?? []).map((c) => ({ id: c.chunk, title: c.title })),
    isFallback: m.isFallback ?? false,
    attachments: (m.attachments ?? []).map((a) => ({
      id: a.toString?.() ?? a,
      url: `/api/v1/uploads/${a.toString?.() ?? a}/raw`,
    })),
    createdAt: m.createdAt,
  };
}

export default router;

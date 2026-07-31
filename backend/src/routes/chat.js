import { Router } from 'express';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { requireAuth, requireClinician, resolvePatientScope } from '../middleware/auth.js';
import { validate, q } from '../middleware/validate.js';
import { asyncHandler, notFound, badRequest } from '../middleware/errors.js';
import { ROLES } from '../models/User.js';
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
      // The earlier turn this message answers, so a reply that lands hours
      // later still says what it is about.
      replyTo: z.string().optional(),
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
      replyTo: req.body.replyTo,
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
      // The earlier turn this message answers, so a reply that lands hours
      // later still says what it is about.
      replyTo: z.string().optional(),
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
        replyTo: req.body.replyTo,
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
    // Messages this patient chose to hide stay in the record but leave their view.
    const filter = { session: session._id, hiddenFor: { $ne: req.user._id } };
    const [items, total] = await Promise.all([
      ChatMessage.find(filter)
        .sort({ seq: 1 })
        .skip(skip)
        .limit(limit)
        .populate('sender', 'name')
        .populate('replyTo', 'content role')
        .populate('attachments', 'kind mimeType transcript')
        .lean(),
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
 * The patient's conversation, read by a clinician.
 *
 * The patient-facing history route is scoped to `req.user`, so a doctor cannot
 * use it. This returns the same thread â€” assistant turns, the patient's own
 * words and any clinician replies â€” so the clinic reads exactly what the
 * patient reads, rather than a separate inbox showing half the story.
 */
router.get(
  '/patients/:patientId/thread',
  requireAuth,
  requireClinician,
  resolvePatientScope,
  validate({ query: pageParams }),
  audit('read', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const session = await ChatSession.findOne({ patient: req.patientId, isArchived: false })
      .sort({ lastMessageAt: -1 })
      .lean();

    // Messages are fetched by patient, not by session. The clinic needs the
    // whole history â€” a patient's care is one continuous story, and an earlier
    // exchange is often exactly the context that explains today's question.
    // It also heals threads already split by sessions created per message
    // before that was fixed.
    const total = await ChatMessage.countDocuments({ patient: req.patientId });

    if (!session && total === 0) {
      // No conversation yet is a normal state, not an error: the clinic may be
      // reaching out first. An empty thread lets the composer open regardless.
      return res.json({
        session: null,
        items: [],
        page: 1,
        limit: 0,
        total: 0,
        hasMore: false,
        patient: req.patientUser
          ? {
              id: req.patientUser._id,
              name: req.patientUser.name,
              phone: req.patientUser.phone,
              // The clinician's conversation header shows the photo the patient
              // set, so the clinic sees the same face the patient chose.
              avatarUrl: req.patientUser.avatarAssetId
                ? `/api/v1/uploads/${req.patientUser.avatarAssetId}/raw` 
                : null,
            }
          : null,
      });
    }

    const { page, limit, skip } = q(req);
    // Newest first so a long history returns its most RECENT page, not its
    // oldest — the clinic was missing the latest messages on any thread past the
    // limit. Ordered by time, not seq: seq restarts per session, so it cannot
    // order a history that spans several. The app re-sorts ascending to display.
    const items = await ChatMessage.find({ patient: req.patientId, hiddenFor: { $ne: req.user._id } })
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate('sender', 'name')
      .populate('replyTo', 'content role')
        .populate('attachments', 'kind mimeType transcript')
      .lean();

    // Opening the thread is what "seen by the clinic" means. Stamped only on
    // the patient's own unseen turns, so the mark says a person from the clinic
    // has read them â€” deliberately in place of a typing indicator, which would
    // promise a reply in seconds that a full clinic list cannot honour.
    await ChatMessage.updateMany(
      { patient: req.patientId, role: 'user', seenByClinicAt: null },
      { seenByClinicAt: new Date() },
    );

    res.json({
      ...paged(items.map(serialiseMessage), { page, limit, total }),
      session: session ? serialiseSession(session) : null,
      patient: req.patientUser
        ? {
              id: req.patientUser._id,
              name: req.patientUser.name,
              phone: req.patientUser.phone,
              // The clinician's conversation header shows the photo the patient
              // set, so the clinic sees the same face the patient chose.
              avatarUrl: req.patientUser.avatarAssetId
                ? `/api/v1/uploads/${req.patientUser.avatarAssetId}/raw` 
                : null,
            }
        : null,
    });
  }),
);

/**
 * The doctor (or staff) speaking directly into the patient's assistant thread.
 *
 * There is deliberately no separate doctor-patient inbox. The assistant handles
 * what it safely can and refers the rest to the clinic; a reply that arrived in
 * a different screen would split one clinical conversation in two, and neither
 * half would carry the context of the other. So a clinician's words land in the
 * same thread the patient is already reading, as `role: 'clinician'` â€” a role
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
  validate({
    body: z.object({
      content: z.string().trim().min(1).max(4000),
      // A clinician can reply with a voice note too — faster between patients,
      // and the patient hears reassurance that text cannot carry.
      attachments: z.array(z.string()).max(5).default([]),
    }),
  }),
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
    // a count â€” an archived or partially deleted history would collide.
    const last = await ChatMessage.findOne({ session: session._id }).sort({ seq: -1 }).select('seq').lean();

    const message = await ChatMessage.create({
      session: session._id,
      patient: req.patientId,
      seq: (last?.seq ?? -1) + 1,
      role: 'clinician',
      sender: req.user._id,
      content: req.body.content,
      language: session.language,
      attachments: req.body.attachments,
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

/** Pin or unpin a message so it stays at the top of the thread. */
router.post(
  '/messages/:id/pin',
  requireAuth,
  validate({ body: z.object({ pinned: z.boolean() }) }),
  audit('update', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const message = await findVisibleMessage(req);
    message.pinnedAt = req.body.pinned ? new Date() : null;
    message.pinnedBy = req.body.pinned ? req.user._id : null;
    await message.save();
    res.json({ id: message._id, pinned: Boolean(message.pinnedAt) });
  }),
);

/**
 * Hide a message from the caller's own view.
 *
 * Never deletes. The conversation is part of a medical record, and an answer
 * the clinic acted on has to remain readable afterwards.
 *
 * A message carrying an emergency verdict cannot be hidden at all: it is the
 * evidence the clinic was paged, and losing it would break the audit trail at
 * the one point where it matters most.
 */
router.post(
  '/messages/:id/hide',
  requireAuth,
  audit('update', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const message = await findVisibleMessage(req);

    if (message.triage?.urgency === 'emergency' || message.alert) {
      throw badRequest(
        'This message is part of an emergency record and cannot be hidden. It shows the clinic was alerted.',
      );
    }

    await ChatMessage.updateOne({ _id: message._id }, { $addToSet: { hiddenFor: req.user._id } });
    res.status(204).end();
  }),
);

router.post(
  '/messages/:id/unhide',
  requireAuth,
  audit('update', 'ChatMessage'),
  asyncHandler(async (req, res) => {
    const message = await findVisibleMessage(req);
    await ChatMessage.updateOne({ _id: message._id }, { $pull: { hiddenFor: req.user._id } });
    res.status(204).end();
  }),
);

/**
 * Loads a message the caller is entitled to act on: their own thread if they
 * are the patient, any patient's if they are clinical staff.
 */
async function findVisibleMessage(req) {
  const filter = { _id: req.params.id };
  if (req.user.role === ROLES.PATIENT) filter.patient = req.user._id;

  const message = await ChatMessage.findOne(filter);
  if (!message) throw notFound('Message not found');
  return message;
}

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
    pinned: Boolean(m.pinnedAt),
    replyToId: m.replyTo
      ? (m.replyTo._id ? String(m.replyTo._id) : (m.replyTo.toString?.() ?? String(m.replyTo)))
      : null,
    // Text of the quoted turn, so the reply renders its quote on every device
    // without needing the original message loaded on that side.
    replyPreview:
      m.replyTo && typeof m.replyTo === 'object' && m.replyTo.content != null
        ? { content: String(m.replyTo.content).slice(0, 160), role: m.replyTo.role ?? null }
        : null,
    seenByClinicAt: m.seenByClinicAt ?? null,
    content: m.content,
    language: m.language,
    urgency: m.triage?.urgency ?? 'routine',
    redFlags: m.triage?.redFlags ?? [],
    citations: (m.citations ?? []).map((c) => ({ id: c.chunk, title: c.title })),
    isFallback: m.isFallback ?? false,
    // Populated attachments carry kind and mimeType so the client knows whether
    // to draw a thumbnail or an audio player; an unpopulated id still yields a
    // usable url, which is what the streaming path sends before it reloads.
    attachments: (m.attachments ?? []).map((a) => {
      const id = (a?._id ?? a).toString?.() ?? a;
      return {
        id,
        url: `/api/v1/uploads/${id}/raw`,
        kind: a?.kind ?? null,
        mimeType: a?.mimeType ?? null,
        // Shown under a voice note so the thread stays skimmable without
        // playing every clip — and readable at all for a deaf patient.
        transcript: a?.transcript ?? null,
      };
    }),
    createdAt: m.createdAt,
  };
}

export default router;

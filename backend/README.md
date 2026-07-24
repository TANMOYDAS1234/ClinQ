# AKD Care — Backend

API server for the Dr. Amit Kumar Dey AI Patient Care application.

Node 20+ · Express · MongoDB (Mongoose) · Gemini

---

## Quick start

```bash
cd backend
npm install
cp .env.example .env          # then fill in GEMINI_API_KEY
npm run seed                  # demo doctor, staff, 3 patients with 60 days of history
npm run seed:knowledge        # doctor-approved knowledge base + embeddings
npm run dev
```

Server listens on `http://localhost:4000/api/v1`. Health check: `GET /api/v1/health`.

Required in `.env`: `MONGODB_URI`, `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `GEMINI_API_KEY`.
The process refuses to start if any are missing — see [src/config/env.js](src/config/env.js).

Generate secrets with:
```bash
node -e "console.log(require('crypto').randomBytes(48).toString('base64url'))"
```

### Demo logins

| Role    | Phone           | Password       | Notes                             |
|---------|-----------------|----------------|-----------------------------------|
| Doctor  | `+919830000001` | `Doctor@1234`  | Full doctor dashboard             |
| Staff   | `+919830000002` | `Staff@1234`   | Alerts + appointments             |
| Patient | `+919830000011` | `Patient@1234` | Rahul Das — poor control, Bengali |
| Patient | `+919830000012` | `Patient@1234` | Sunita Sharma — good control, Hindi |
| Patient | `+919830000013` | `Patient@1234` | Ayesha Rahman — Type 1, English   |

---

## The one thing to understand before changing anything

**Emergency triage is deterministic. The language model never decides whether a patient is in danger.**

Every patient message runs through [`src/services/triage/`](src/services/triage/) *before* Gemini is
called. Hard-coded thresholds and multilingual regex rules produce an urgency verdict. That verdict is
then injected into the prompt as an already-decided fact, and the model is instructed that it may
raise urgency but never lower it.

This matters because it means:

- A chest-pain message escalates to the clinic **even if the Gemini API is down**, rate-limited, or
  returns nonsense. The alert is raised before the model is called.
- If generation fails, the patient still receives correct emergency instructions — written out in
  full in English, Bengali and Hindi in [`src/services/ai/prompts.js`](src/services/ai/prompts.js).
- Triage behaviour is unit-testable without mocking an LLM. See [`tests/triage.test.js`](tests/triage.test.js).

Thresholds live in one file, [`src/services/triage/thresholds.js`](src/services/triage/thresholds.js).
**They must be reviewed and signed off by Dr. Dey before any change ships.**

The same principle applies to the foot module: rule-based risk and AI image risk are computed
separately and the **higher** of the two always wins.

---

## Layout

```
src/
  config/         env validation, mongo connection, logger (PHI-redacting)
  models/         Mongoose schemas — 17 collections
  middleware/     auth, patient scoping, validation, audit, error handling
  routes/         REST endpoints (see ../API_CONTRACT.md)
  services/
    triage/       ← deterministic rule engine. Safety-critical.
      thresholds.js    clinical constants
      redFlagRules.js  multilingual symptom patterns (en/bn/hi)
      engine.js        classification + free-text vital extraction
    ai/
      gemini.js     SDK wrapper: retries, safety settings, structured output
      rag.js        retrieval over approved knowledge only
      prompts.js    system prompt + written fallbacks in 3 languages
      assistant.js  orchestrates: triage → escalate → retrieve → generate
      vision.js     foot image assessment, eye report explanation
    analytics.js    health score, adherence, glucose trends, risk banding
    alerts.js       escalation records + de-duplication
  knowledge/      seed content for the knowledge base
scripts/          seed.js, seedKnowledge.js
tests/            unit tests + manual/chatSmoke.js
```

---

## Testing

```bash
npm test                              # 48 unit tests, no DB or API key needed
node tests/manual/chatSmoke.js        # end-to-end triage, needs a running server
```

`chatSmoke.js` uses `fetch` rather than curl deliberately. **Passing Bengali or Hindi text through a
Windows shell silently mangles it to `?` characters**, which turns an emergency into a routine
message and makes the triage engine look broken when it is not. Always exercise multilingual paths
from Node.

---

## Design notes

**Authorization.** Every clinical route funnels through `resolvePatientScope`
([src/middleware/auth.js](src/middleware/auth.js)). Patients can only ever reach their own record;
clinicians must name a patient explicitly. One place to audit rather than id comparisons scattered
across handlers. Verified: cross-patient access returns 403, patient→doctor endpoint returns 403.

**Audit logging.** Reads and writes of patient data append to `AuditLog` — required for healthcare
compliance and the only way to answer "who saw this record". Metadata only; never request bodies.

**Refresh token rotation.** Tokens are stored hashed. Reuse of a consumed token revokes the entire
token family, on the assumption it was stolen.

**Prescriptions are immutable.** Corrections create a new version pointing at `supersedes`. An
edited prescription with no history is a compliance problem.

**Knowledge base.** Only `status: 'approved'` chunks are retrievable. Editing approved content
resets it to `pending_review` — otherwise a reviewed-safe chunk could be silently rewritten and keep
serving patients. Every assistant answer stores its citations, so the doctor dashboard can trace any
answer back to the approved source that grounded it.

**RAG backend.** Uses Atlas `$vectorSearch` when `USE_ATLAS_VECTOR_SEARCH=true`, otherwise
in-process cosine similarity — a single clinic's corpus is small enough that brute force is fine,
and it keeps local development working against a plain `mongod`. Falls back to Mongo text search if
embeddings are unavailable entirely.

**Uploads** are re-encoded through `sharp`, which strips EXIF. Patient foot photos otherwise carry
the GPS coordinates of their home.

---

## Known gaps

These are stubbed at a clean boundary, not scattered through the code:

- **Push notifications** — `src/services/notifications.js` persists alerts and `notifiedAt`
  timestamps for real, but logs instead of delivering. Swap the `deliver()` function for FCM/APNs.
  For the emergency path, an SMS gateway is worth adding: a patient in DKA may not open the app.
- **Teleconsultation** — appointments carry a `roomId`; no video provider is wired up.
- **Prescription PDF** — served as styled HTML for the client to print/save, avoiding a
  headless-Chrome dependency. Swap for a real PDF renderer if a stored file is required.
- **Knowledge base content** — the seed is drafted from mainstream guidance (ADA/IDF/WHO) as a
  starting point. **It must be reviewed and approved by Dr. Dey before use with real patients.**
- **Lab value extraction** from uploaded PDFs is manual; the schema supports structured values but
  nothing parses them automatically yet.

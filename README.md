# AKD Care

AI-assisted patient care application for **Dr. Amit Kumar Dey**, Consultant Physician and Diabetologist.

A cross-platform mobile app (Android + iOS) that helps patients manage diabetes and lifestyle
disease between clinic visits, with a 24/7 AI assistant grounded in a doctor-approved knowledge
base, and a doctor-side dashboard for monitoring and escalation.

```
zzzz/
├── backend/          Node + Express + MongoDB + Gemini        → backend/README.md
├── mobile/           Flutter (Android + iOS)                  → mobile/README.md
└── API_CONTRACT.md   The API spec both sides are built against
```

---

## Run it

**Prerequisites:** Node 20+, MongoDB 6+ running locally, Flutter 3.29+, a Gemini API key
([get one free](https://aistudio.google.com/apikey)).

```bash
# 1. Backend
cd backend
npm install
cp .env.example .env          # set GEMINI_API_KEY, generate the two JWT secrets
npm run seed                  # demo doctor, staff, 3 patients, 60 days of history
npm run seed:knowledge        # doctor-approved knowledge base + embeddings
npm run dev                   # → http://localhost:4000/api/v1

# 2. Mobile
cd ../mobile
flutter pub get
flutter run                   # Android emulator reaches the host at 10.0.2.2
```

Demo logins are listed in [backend/README.md](backend/README.md#demo-logins).
Start with `+919830000011` / `Patient@1234` — a poorly-controlled patient with alerts already open.

---

## The design decision that matters most

**Emergency triage is deterministic. The language model never decides whether a patient is in danger.**

Every patient message is assessed by a hard-coded rule engine *before* Gemini is called. That verdict
is then handed to the model as an already-settled fact, with instructions that it may raise urgency
but never lower it.

The consequence: if a patient types *"I have chest pain"* and the Gemini API is down, rate-limited,
or returns something unhelpful — the clinic is still paged, and the patient still receives correct
emergency instructions in their own language. The escalation happens before the model is ever
called, and the fallback text is written out in full in English, Bengali and Hindi.

An LLM that hedges on a myocardial infarction is not an acceptable failure mode. So the LLM is not
allowed to be the thing that decides.

Everything else follows from this: thresholds live in one reviewable file, triage is unit-testable
without mocking an LLM, and the foot module takes the **higher** of rule-based and AI-assessed risk
rather than trusting the model's optimism.

---

## Features

| # | Module | Status |
|---|--------|--------|
| 1 | AI Health Assistant — RAG over approved content, multilingual, emergency detection | Complete |
| 2 | Diabetes management — glucose, HbA1c, insulin, medication, diet, exercise, weight, water | Complete |
| 3 | Diabetic foot care — image upload, AI + rule risk assessment, wound progression | Complete |
| 4 | Eye care — report upload, plain-language AI explanation, referral urgency | Complete |
| 5 | Appointments — booking, rescheduling, queue management, teleconsult scaffold | Complete (no video provider) |
| 6 | Digital prescriptions — printable, medication sync, archive, lab uploads | Complete (HTML print view) |
| 7 | Emergency triage — deterministic rules, escalation, staff notification | Complete (push is stubbed) |
| 8 | Patient dashboard — health score, trends, adherence, recommendations | Complete |
| 9 | Doctor dashboard — analytics, risk segmentation, alerts, AI chat review | Complete (API + Flutter placeholder) |
| 10 | Multilingual — English, Bengali, Hindi | Complete |

Triage covers every emergency named in the brief: blood sugar > 400, severe hypoglycaemia, chest
pain, breathing difficulty, sudden vision loss, and severe diabetic foot infection — plus stroke
signs, suspected DKA, and self-harm risk, in all three languages.

---

## Verification

```bash
cd backend
npm test                              # 48 unit tests — triage engine, no DB or API key needed
node tests/manual/chatSmoke.js        # 13 end-to-end triage cases across en/bn/hi
node tests/manual/moduleSmoke.js      # 34 checks across the clinical modules
```

All passing as of the last run. The smoke tests need a running server and a seeded database.

> **Note for anyone testing by hand on Windows:** passing Bengali or Hindi text through Git Bash
> or PowerShell to `curl` silently mangles it to `?` characters, which makes the triage engine look
> catastrophically broken when it is fine. Use the Node smoke tests, which send UTF-8 correctly.

---

## Before this touches a real patient

This is a working, tested application — not a certified medical device. The following are
non-negotiable prerequisites for clinical use:

1. **Dr. Dey must review and approve the knowledge base.** The seed content in
   `backend/src/knowledge/seedContent.js` is drafted from mainstream guidance (ADA, IDF, WHO) as a
   starting point. The `status` field and approval endpoints exist precisely so that approval is an
   explicit, auditable act by a named clinician.
2. **Dr. Dey must sign off the clinical thresholds** in `backend/src/services/triage/thresholds.js`.
3. **Wire up real push notifications and an SMS fallback.** Alerts are persisted and the transport
   boundary is clean, but nothing is delivered yet — and a patient in DKA may not open the app.
4. **Regulatory review.** Telemedicine practice, medical device classification, and data protection
   obligations (India's DPDP Act, and HIPAA/GDPR if patients are ever outside India) all need
   professional advice before launch.
5. **Deploy over TLS**, with secrets in a managed store rather than a `.env` file, and enable
   MongoDB encryption at rest and authentication.
6. **Independent clinical safety review of the triage rules**, ideally including a red-team pass
   with real patient phrasings in all three languages.

The audit log, immutable prescriptions, PHI-redacting logger, consent timestamps, and citation
tracking are all in place to support that review — but they are the foundation for compliance work,
not a substitute for it.

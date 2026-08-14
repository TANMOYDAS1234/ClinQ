# ClinQ — Doctor / Clinician Panel: Full Workflow

A complete map of the doctor (and clinic-staff) side of the app: every bottom-nav
tab, the sections inside each, what each section does, and every sub-screen
reachable from them. Use this as the structural reference before any redesign.

> **Scope:** the clinician role (doctor + staff). The patient and dietician panels
> are separate. Colour palette is defined in `mobile/lib/core/theme/app_colors.dart`
> and stays fixed across any redesign.

---

## 0. At a glance

The doctor panel is a **4-tab bottom navigation** shell
(`clinician_shell.dart`), plus a set of deeper **sub-screens** that are *pushed on
top* of the shell (they are not tabs).

| # | Tab | Icon | What it is | Route |
|---|-----|------|-----------|-------|
| 0 | **Home** | dashboard | The clinic's pulse at a glance (live dashboard) | `/clinician/dashboard` |
| 1 | **Care** | groups | Doctor ↔ patient conversation inbox | `/clinician/patients` |
| 2 | **Nutrition** | restaurant | Dietician ↔ patient conversation inbox (doctor watches / steps in) | `/clinician/nutrition` |
| 3 | **Profile** | person | Identity + settings + launcher for all clinical tools | `/clinician/more` |

The **two conversation streams** (Care vs Nutrition) mirror how threads are modelled
on the server (`kind: care` vs `kind: nutrition`). Everything else — alerts,
appointments, clinics, knowledge, dieticians, feedback, the patient record, the
consult flow — is reached from **Home cards** or the **Profile hub**.

```
Doctor app
├── [Tab 0] Home ......... dashboard cards → jump into patients / alerts / reviews
├── [Tab 1] Care ......... patient chat inbox → Patient Thread → Patient Record
├── [Tab 2] Nutrition .... dietician-chat inbox → Chat Review detail
└── [Tab 3] Profile ...... settings + launcher:
        ├── Clinical alerts
        ├── Clinic care (dieticians / invite / food-log cadence)
        ├── Chat review
        ├── Knowledge base
        ├── Patient feedback
        ├── Edit profile
        ├── Prescription letterhead (professional details + signature)  [doctor only]
        └── (Appointments, Clinics — routed, reachable from hub shortcuts)

Sub-screens (pushed over the shell):
   Patient Profile (record + prescribe)  ├─ Consult flow (Vitals→Diagnosis→Advice)
                                         ├─ Prescriptions list (PDF)
                                         └─ Patient Thread (chat)
   Add Patient · Alerts · Appointments · Clinics(+edit) · Knowledge(+edit)
   · Chat Review(+detail) · Dieticians · Feedback
```

---

# TAB 0 — Home (Doctor Dashboard)

**File:** `clinician_dashboard_screen.dart` · **Purpose:** a live operational
dashboard — refreshes every 20s, on resume, and on pull-to-refresh. It answers
"what needs me right now?" and routes into the detail.

| # | Section | What it shows / does | Tap leads to |
|---|---------|---------------------|--------------|
| 1 | **Header** | ClinQ wordmark + doctor avatar | avatar → Profile |
| 2 | **Headline counts** | **Total patients** (+N today) and **Flagged chats** (to review) | patients / chat-review |
| 3 | **Alert strip** | Up to 4 rows: **Vitals warning** (critical patients), **High priority** (action items), **New messages** (care unread), **Nutrition messages** (unread) | patients / alerts / nutrition |
| 4 | **Monitoring strip** | Continuous-monitoring roll-up: **Check-ins overdue** (patients gone quiet), **Trending worse** (drifting out of range), or an "all up to date" reassurance | patients |
| 5 | **Needs attention** | Top 6 patients ranked by open alerts → risk score → overdue | patient record |
| 6 | **Live Triage Queue** | Top 3 open alerts worst-first (name, time, detail, severity + type tag); "View All Triage (N)" footer | patient thread / alerts |
| 7 | **Nutrition Reviews** | Patients whose dietician-review cadence is due ("Day X/Y", flag + detail), each with a **Review Log** button | patient record |

---

# TAB 1 — Care (Patient message inbox)

**File:** `patients_screen.dart` · **Purpose:** the doctor ↔ patient conversation
inbox (a chat list, **not** a clinical directory). Polls every 3s; rows sort
unread-first then newest.

**Sections / controls**
- **Header** — logo + doctor avatar (→ Profile).
- **Section bar** — heading **"Patient Messages"** with an **Unread / Show all** toggle.
- **Search field** — debounced search over patients + messages.
- **Conversation list** — one grouped card of rows. Each **conversation row** shows:
  - avatar, name (bold if unread), timestamp, last-message preview (with "You:" prefix + media glyph),
  - a green **unread-count** disc,
  - a **"Needs attention"** chip for emergency/urgent threads,
  - a **monitor strip**: glucose sparkline, HbA1c value, trend arrow, and a **"Check-in due"** chip when overdue.
- **FAB "Add patient"** → patient registration.

**Tap a row → Patient Thread** (the chat). From there → the full Patient Record.

---

# TAB 2 — Nutrition (Dietician-chat inbox)

**File:** `nutrition_inbox_screen.dart` · **Purpose:** every dietician ↔ patient
conversation, so the doctor can watch and step in. Built to mirror the Care tab
(polls 3s, unread-first). Query is fixed to `kind: nutrition`.

**Sections / controls**
- **Header** — logo + doctor avatar (→ Profile).
- **Section bar** — heading **"Nutrition"** with the **Unread / Show all** toggle.
- **Search field** — client-side over name + last message.
- **Conversation list** — same row style as Care, but the preview carries a role
  prefix: **"Dietician:" / "You:" / "AI:"**. No "Add patient" FAB.

**Tap a row → Chat Review detail** (the full conversation, with AI audit trail) —
*not* the patient thread.

---

# TAB 3 — Profile (settings + clinical-tools launcher)

**File:** `clinician_more_screen.dart` · AppBar **"Profile"**. The clinician
counterpart of the patient profile and the launcher for every tool.

| # | Section | Contents |
|---|---------|----------|
| A | **Header** | avatar (tap = change photo, long-press = fullscreen), name, phone, role chip (**Doctor** / **Clinic staff**) |
| B | **Appearance** | theme selector (light/dark/system) |
| C | **Language** | English / Bengali / Hindi chips |
| D | **Account** | **Edit profile** → edit screen |
| E | **Clinic tools** *(the launcher)* | see rows below |
| F | **Prescription letterhead** *(doctor only)* | **Professional details** (qualifications / specialty / registration no.) · **Digital signature** (upload/replace image embedded in Rx PDFs) |
| G | **Security** | **App lock** toggle |
| H | **Clinic** | **Clinic phone number** card (edit the clinic's public number) |
| I | **App** | **About** (version dialog) |
| J | **Log out** | with confirmation; footer shows app version |

**Clinic-tools launcher rows (section E):**

| Row | Subtitle | Destination |
|-----|----------|-------------|
| **Clinical alerts** | — | Alerts screen |
| **Clinic care** | "Dieticians, invites and food-log review" | Dieticians screen |
| **Chat review** | — | Chat Review list |
| **Knowledge base** | — | Knowledge list |
| **Patient feedback** | "What patients say about the clinic and the app" | Feedback inbox |

*(Messages is intentionally omitted here — it's the first tab. Appointments &
Clinics are routed and reachable as hub shortcuts.)*

---

# SUB-SCREENS (pushed over the shell)

These are the deeper screens. Most are entered from a **patient's record header**
(Consult / Prescription / Message / Call) or from the **Profile hub**.

---

## S1 — Patient Profile (record + prescribe)

**File:** `patient_profile_screen.dart` · Route `/clinician/patients/:id` ·
**Purpose:** the doctor's working screen for one patient — *"writing the
prescription IS the consultation."* Identity at top, the full read-only clinical
record in the middle, the prescribing form at the bottom.

### Header (`_ProfileHeader`)
- Avatar, name, `age • gender • phone`, address (no patient ID shown by design).
- **Risk pill** (warning triangle when high/critical) + **diabetes-type** pill.
- **Action buttons:** **Call** · **Message** (→ thread) · **Consult** (→ consult flow) · **Prescription** (→ Rx list).
- **Complaint chip** → bottom sheet with the full presenting complaint.

### Clinical record — read side (`PatientRecordSections`, from `patient_detail_screen.dart`)
| Section | What it does |
|---------|--------------|
| **Metrics grid** | 6 tiles: Health score, **Adherence %** (tap → Week/Month/Year sheet with per-medicine breakdown), Medicines (active count), Fasting sugar, Last HbA1c, Est. HbA1c |
| **Measurements** | Height, Weight, BMI, Waist, BP, Pulse, SpO₂ (hidden if none) |
| **Dietician** | "Covered by clinic dietician" or the restricted name; **Restrict/Change** sheet (radio list + inline "add a new dietician" form; offered only with ≥2 dieticians) |
| **HbA1c history** | latest 4 (colour-coded ≥9 danger / ≥7 warning) + **View all** modal |
| **Test reports** | up to 12 uploaded reports; tap → image full-screen or PDF open (auth download); **red "Out of range"** summary; analyte chips with ranges + ↑/↓; **Lab trends** sparklines for markers seen on ≥2 reports |
| **Recent alerts** | up to 8, severity-coloured, with status pill |
| **Previous consultations** | dated expandable tiles → Diagnosis, Medicines, Tests advised, Advice, Follow-up, By (doctor) |
| **Assistant context** | collapsible "what the AI assistant sees" (exact context string) |

### Prescribing form ("Clinical Actions")
| Card | Sub-sections |
|------|--------------|
| **Medication** | **Currently on** (active meds, each with a **Stop** button) · **Add medication** (collapsible): name, dosage, duration, **Frequency** shorthand chips, **Timing** (AC/With/PC/Any), **Route** chips, live shorthand badge + plain-language preview; "Add another medication" |
| **Lab Tests** | **Already ordered** (✓ received / ⏳ pending) + **Reports received** · **Add tests** (collapsible): free-text add, diabetes lab catalog grouped by category, per-panel sub-tests listed |
| **Clinical Advice** | **Previous advice** (tap to reuse) · **Diagnosis** (multiline, one per line) · **General advice** (multiline) |
| **Follow-up** | Next-visit date picker |
| **Send Prescription** | builds items + diagnosis + labs + advice + follow-up → creates the prescription; clears the form (stays on patient) |

---

## S2 — Consult flow

**File:** `consult_screen.dart` · Route `/clinician/patients/:id/consult` ·
**Purpose:** a guided **3-step stepper** that ends in a generated prescription PDF.
Progress dots at top; Back + Next/Generate bar at bottom.

| Step | Captures |
|------|----------|
| **1 · Vitals** *(all optional, measured this visit)* | Height, Weight, BP systolic/diastolic, Heart rate, SpO₂, Blood sugar · **Presenting complaint** (multiline) + checkbox **"Show this complaint on the prescription"** |
| **2 · Diagnosis** | **Waist** (examination) · **Previous diagnosis** reuse chips · **Diagnosis catalog** (grouped, tap to select, printed on Rx) · "Add another diagnosis" free-text |
| **3 · Advice** | **Last prescription** recap · **Medicines** (reuse-last chips + medicine cards: name, strength, days, frequency, route, meal relation, live shorthand+plain preview; "Add medicine") · **Lab tests advised** (catalog + reuse + custom) · **General advice** (reuse-last + common-advice chips + free text) · **Follow-up date** · **Digital signature** (upload/change) |

**Generate:** validates vitals + diagnosis (jumps back to the offending step),
requires ≥1 medicine, saves vitals first, then creates the prescription, and
replaces into the prescriptions list.

---

## S3 — Prescriptions list

**File:** `prescription_list_screen.dart` · Route `/clinician/patients/:id/prescriptions` ·
**Purpose:** the patient's prescriptions, latest first. Each **card**: issued
date/time, reference number, diagnosis line, medicine count + tests-advised count,
follow-up, and a **Download PDF** button (auth download → opens in the phone's
viewer). Empty state prompts a consultation.

---

## S4 — Chat Review

**Purpose:** the assistant-conversation review queue — threads the assistant or a
patient flagged, with the AI safety-audit trail preserved.

- **List** (`chat_review_screen.dart`) — AppBar "Chat review" with **Flagged / All
  chats** tabs (care threads only; nutrition has its own tab). Inbox-style rows:
  avatar, name, preview + media icon, timestamp, unread badge, urgency pill, flag
  icon, and a **Clear flag** action. Tap → detail.
- **Detail** (`chat_review_detail_screen.dart`) — a **full chat** (not read-only):
  pinned-message banner, auto-scroll to the flagged turn, role-aware message
  bubbles (Patient / You / Assistant / Dietician), long-press actions **Copy /
  Reply / Pin / Delete for me / Delete for everyone**, and **AI audit chips**
  (urgency, rule-driven, fallback, sources count, latency, sources line). A full
  composer (text / photo / document / voice) posts as the clinician + a **Reviewed**
  action clears the flag.

---

## S5 — Patient Thread (chat)

**File:** `patient_thread_screen.dart` · Route `/clinician/patients/:id/thread` ·
**Purpose:** the clinician's view of the patient's real conversation, rendered with
the same bubbles the patient sees. Polls every 3s.

- **AppBar:** avatar + name; **"Patient record & prescribe"** (→ record) and **Call**.
- **Body:** chat wallpaper, message list, jump-to-latest button.
- **Composer:** attach (photo camera / gallery / document), text, **voice record**, send; reply-preview bar.
- **Message actions:** reply, pin, hide, delete-for-everyone (own turns); tap a quote scrolls to it.

---

## S6 — Knowledge base

**Purpose:** the doctor-approved knowledge the AI assistant answers from (only
`approved` entries are served).

- **List** (`knowledge_screen.dart`) — status filter **All / Approved / Pending /
  Draft / Retired**; each row: title + status pill, content preview, tag chips
  (category, language, version, "no embedding"). FAB **Add entry**.
- **New/Edit** (`knowledge_edit_screen.dart`) — Title, Document ID + Section,
  Content, **Language** chips, **Category** dropdown, Source citation, Tags.
  Actions: **Save/Create**, **Approve** (when editing & unapproved), **Retire**.
  Editing content sends it back to "pending review."

---

## S7 — Clinics

**Purpose:** clinic + availability management.

- **List** (`clinics_screen.dart`) — each row: name (+ "Inactive" pill), location,
  "{days} · {slot} min slots". FAB **Add clinic**.
- **New/Edit** (`clinic_edit_screen.dart`) — Details (name, address, city, phone,
  map link); **Slot length** chips (10/15/20/30/45 min); **Accepting bookings**
  toggle; **Weekly availability** (per-day time windows); **Closures & holidays**
  (one-off dates). Save creates/updates; Deactivate when editing.

---

## S8 — Appointments admin

**File:** `appointments_admin_screen.dart` · **Purpose:** the clinic diary.
Scope **Today / Upcoming / All** + status filter **All / Requested / Confirmed /
Completed / Cancelled**. Each appointment card has a manage sheet with
status-appropriate transitions:
- requested → Confirm, Mark no-show
- confirmed → Check in, Start consultation, Mark no-show
- checked-in → Start consultation
- in-consultation → Complete (optional notes)
- plus **Cancel** (with reason) while active.

---

## S9 — Alerts (clinical triage)

**File:** `alerts_screen.dart` · **Purpose:** triage of alerts raised by the
assistant + tracking rules. Status filter **Open / Acknowledged / Resolved / All**.
Each **alert card**: severity pill, status, time, title, patient name + phone (call
icon), detail. Actions: **Acknowledge** (open only) and **Resolve** (optional
notes) — both refresh the dashboard immediately.

---

## S10 — Feedback inbox

**File:** `feedback_inbox_screen.dart` · **Purpose:** what patients said about the
clinic and the app — **read-only** (feedback is authored in the patient panel).
Heading "Patient Feedback" + filter chips **All / The clinic / The app**. Each
card: unread stripe, heading from the patient's opening words, star rating (if
rated), message, "{patient} · {about} · {date}", and a **Mark reviewed** action.

---

## S11 — Dieticians / Clinic care

**File:** `dieticians_screen.dart` · AppBar **"Clinic care"** · **Purpose:** the
clinic's dieticians (one added here covers every patient).
- **Info banner** (scope explainer).
- **Food-log review** card — clinic-wide cadence; sheet with presets **Daily /
  Every 3 days / Weekly / Every 2 weeks / Monthly**.
- **Invite a dietician** card — shows the invite code + **Copy invite code** (only
  when a code exists).
- **Dieticians list** — avatar (tap = full-screen), name, phone.
- **Add dietician** FAB → sheet (Full name / Mobile / Password).

---

## S12 — Patient registration (Add patient)

**File:** `add_patient_screen.dart` · Route `/clinician/patients/new` · AppBar
**"Register patient"** · **Purpose:** the receptionist's intake form.
- **Patient details** *(required):* Full name, Age, Gender, Phone (+91), Address.
- **Vitals — optional:** Height, Weight, BP systolic/diastolic, Heart rate, SpO₂, Blood sugar.
- **Complaints — optional:** presenting complaint.
- **Register patient** → creates the record and opens it.

---

# Appendix — Route map

| Route | Screen |
|-------|--------|
| `/clinician/dashboard` | Home (dashboard) — Tab 0 |
| `/clinician/patients` | Care inbox — Tab 1 |
| `/clinician/nutrition` | Nutrition inbox — Tab 2 |
| `/clinician/more` (+ `/edit`) | Profile hub — Tab 3 |
| `/clinician/patients/:id` | Patient Profile (record + prescribe) |
| `/clinician/patients/:id/consult` | Consult flow |
| `/clinician/patients/:id/prescriptions` | Prescriptions list |
| `/clinician/patients/:id/thread` | Patient Thread (chat) |
| `/clinician/patients/new` | Add Patient |
| `/clinician/alerts` | Alerts |
| `/clinician/appointments` | Appointments admin |
| `/clinician/clinics` (+ `/new`, `/edit`) | Clinics |
| `/clinician/chat-review` (+ `/:id`) | Chat Review list / detail |
| `/clinician/knowledge` (+ `/new`, `/edit`) | Knowledge base |
| `/clinician/dieticians` | Clinic care (dieticians) |
| `/clinician/feedback` | Feedback inbox |

---

# Redesign notes (for the next phase)

- **4 tabs, 12 sub-screens** — the redesign surface is the 4 tab screens + these
  sub-screens; the two inboxes (Care, Nutrition) share a row component, so
  restyling one restyles both.
- **Palette is fixed** — pull tokens from `app_colors.dart`; "redesign" = layout,
  hierarchy, spacing, cards, typography, and iconography, **not** recolouring.
- **Highest-traffic screens** (redesign these first): Home dashboard, Care inbox,
  Patient Profile (record + prescribe), Consult flow.
- **Shared components worth standardising first:** the inbox conversation row, the
  metric/stat tile, the section card + header, the alert/severity pill, the lab
  report row, and the sparkline — restyling these propagates everywhere.

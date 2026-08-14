# ClinQ — Dietician Panel: Full Workflow

A complete map of the dietician side of the app: every bottom-nav tab, the sections
inside each, what each section does, and every sub-screen reachable from them.
Companion to `DOCTOR_PANEL_WORKFLOW.md` and `PATIENT_PANEL_WORKFLOW.md`.

> **Scope:** the dietician role. A dietician only sees the patients a doctor
> assigned to them, and is kept inside the `/dietician/*` tree. Palette lives in
> `mobile/lib/core/theme/app_colors.dart`.

---

## 0. At a glance

The dietician app is a **3-tab bottom navigation** shell (`dietician_shell.dart`) —
the same shape as the doctor's, minus the conversation tabs. A dietician reaches a
patient's chat from *inside* that patient's record, not a separate inbox.

| # | Tab | Icon | What it is | Route → screen |
|---|-----|------|-----------|----------------|
| 0 | **Dashboard** | dashboard | The actionable day: counts, reviews due, plans to send, meals logged | `/dietician/dashboard` → `DieticianDashboardScreen` |
| 1 | **Patients** | groups | The assigned-patient worklist (review-due first) | `/dietician/patients` → `DieticianPatientsScreen` |
| 2 | **Profile** | person | The dietician's own account + settings | `/dietician/profile` → `DieticianProfileScreen` |

**Sub-screens** (pushed over any tab):
- **Patient detail** — `/dietician/patients/:id` → the full clinical picture the dietician plans around.
- **Diet plan editor** — `/dietician/patients/:id/diet` → write/edit and send the plan.
- **Dietician↔patient chat** — `/dietician/patients/:id/chat` → the shared care thread.
- **Edit profile** — `/dietician/profile/edit` → the shared `EditProfileScreen`.

```
Dietician app
├── [Tab 0] Dashboard ... counts → Reviews Due · Waiting for Diet Plan · Latest Meals Logged
├── [Tab 1] Patients .... assigned worklist (review-due first) → Patient detail
└── [Tab 2] Profile ..... appearance · language · edit profile · app lock · logout

Patient detail (from a dashboard row or the Patients list)
   ├── Medical header · Diet plan · Vitals & measurements · Current medicines
   ├── Doctor's advice · Tests ordered · Lab reports · Food log
   ├── [button] Message patient ....... → Dietician↔patient chat
   └── [Diet plan card] ............... → Diet plan editor → "Send to patient"
```

> **One scoping caveat worth knowing:** the backend restricts a dietician to
> *assigned* patients ("A doctor will assign patients to you"), but two dashboard
> strings still read as if clinic-wide ("My Patients", "No patients on the clinic
> list yet"). Behaviour is assigned-only; the copy is just inconsistent.

---

# TAB 0 — Dashboard

**File:** `dietician_dashboard_screen.dart` · **Purpose:** the dietician's day in
one screen — counts, then lapsed reviews, then patients needing a plan, then meals
logged while they were away. Auto-refreshes every 30s + pull-to-refresh.

| # | Section | What it does |
|---|---------|--------------|
| 1 | **Brand header** | logo + wordmark; avatar → Profile |
| 2 | **Greeting** | "Good Morning/Afternoon/Evening, {name}" + "your daily clinical overview" |
| 3 | **Three stat cards** | **My Patients** (+N this week) · **Reviews Due** (danger accent if >0) · **Plans to Send** (accent if >0) |
| 4 | **Reviews Due** worklist | top 3 patients whose review has lapsed — condition subtitle + an age pill ("N days ago"); row → patient detail; "View All" → Patients tab (only if >3) |
| 5 | **Waiting for Diet Plan** worklist | top 3 patients with no plan — "Waiting N days" + a **"Create Plan"** button → diet-plan editor; row → patient detail |
| 6 | **All caught up** | shown only when both worklists are empty |
| 7 | **Latest Meals Logged** | up to 6 recent meal photos (patient name, "logged N ago"); tap → patient detail |

*A patient waiting for a plan is deliberately kept out of the "Reviews Due" list so nobody appears twice.*

---

# TAB 1 — Patients

**File:** `dietician_patients_screen.dart` · **Purpose:** the assigned-patient
worklist, review-due surfaced first.

**Sections / controls**
- **App bar:** "My patients" + "Dietician · {name}"; avatar → Profile.
- **Search** (app-bar bottom): filters by **name or phone**, case-insensitive, with a clear button.
- **Patient list** — sorted review-due first; empty states: "No patients assigned yet / A doctor will assign patients to you" and "No patient matches '{query}'".
- Each **patient card**: avatar, name, a **risk pill** (critical/high/moderate/low), diabetes type, a **"Review due"** amber badge when due, and a chevron. Tap → patient detail.

---

# TAB 2 — Profile

**File:** `dietician_profile_screen.dart` · **Purpose:** the dietician's own account
— the doctor's profile minus the clinic tools (no alerts / knowledge / feedback).

| # | Section | Contents |
|---|---------|----------|
| 1 | **Avatar + identity** | tap avatar = change photo, long-press = fullscreen; name + "Dietician · {phone}" |
| 2 | **Appearance** | Light / Dark / System |
| 3 | **Language** | English / বাংলা / हिन्दी |
| 4 | **Account** | **Edit profile** → `/dietician/profile/edit` |
| 5 | **Security** | **App Lock** switch (biometric; needs one successful unlock to enable) |
| 6 | **App** | **About** (version dialog) |
| 7 | **Log out** | with confirmation |

---

# SUB-SCREENS

## S1 — Patient detail

**File:** `dietician_patient_screen.dart` · Route `/dietician/patients/:id` ·
**Purpose:** the full clinical picture a dietician needs to recommend food *safely*
— the plan sits on top, everything below it is input. A persistent **"Message
patient"** button at the bottom opens the chat.

| # | Section | What it shows |
|---|---------|---------------|
| 1 | **Medical header** | name + risk pill; facts (Diabetes, Age, Gender, Height, Diagnosed-on, Review-every); **Main concern** (chief complaint); **Allergies** (red chips) |
| 2 | **Diet plan** | the plan at a glance (goal, meal chips, "N to avoid") + a **sent-status line** ("Not sent yet" / "Edited since sent" / "Sent {date}"); tap → the diet-plan editor |
| 3 | **Vitals & measurements** | latest BP, blood sugar, weight, BMI, waist, pulse, SpO₂, temp — each its own most-recent reading **with the date taken** (abnormal in red; a never-recorded vital is simply absent) |
| 4 | **Current medicines** | the doctor's active meds (name · strength · dose · times) |
| 5 | **Doctor's advice** | collapsible entries per prescription: diagnosis, general advice, follow-up, by-whom — each dated |
| 6 | **Tests ordered** | last HbA1c + advised tests with "Result in" / "Awaiting result" |
| 7 | **Lab reports** | uploaded reports: transcribed values, a red **"Out of range"** line, and tap-to-open (image full-screen, PDF downloaded) |
| 8 | **Food log** | the patient's recent meals (photo, meal type, time, note) |

*(Sections 3–7 render only when there's data — the screen never shows an empty vitals or advice block.)*

## S2 — Diet plan editor

**File:** `diet_plan_screen.dart` · Route `/dietician/patients/:id/diet` ·
**Purpose:** the durable form of food guidance — one document edited in place.
**Save and Send are deliberately separate** so editing doesn't notify the patient.

**Form sections**
- **Goal** — free text (e.g. "Bring fasting sugar under 130 without cutting rice completely").
- **Meals** — a card per meal: **name**, **time** (picker), **items** (bulleted lines, add/remove), and an optional **per-meal note**; suggestion chips add **Breakfast / Mid-morning / Lunch / Evening snack / Dinner / Other**.
- **Best avoided** — deletable red chips + an add field.
- **Anything else** — a notes field (water, cooking oil, eating out, fasting days…).

**Bottom bar**
- A **status line**: "Saving…" / "Unsaved changes" / "Saved · not sent yet" / "Saved · sent {date}".
- **"Send to patient"** (or "Send the updated plan") — saves first if dirty, then pushes the plan **into the patient's care thread** (chat). Backing out with unsaved edits auto-saves the draft.

## S3 — Dietician↔patient chat

**File:** `dietician_chat_screen.dart` · Route `/dietician/patients/:id/chat` ·
**Purpose:** the dietician's side of the patient's **single shared care thread** —
replies land where the patient and doctor read, never a separate conversation.

- **App bar:** patient avatar + name + "Nutrition chat"; a **Call patient** action.
- **Thread:** chat wallpaper, reversed list (newest at bottom), empty state "Say hello and share your first food guidance", and a **jump-to-latest** button when scrolled up.
- **Bubbles:** role-badged (patient / Doctor / AI Assistant / Dietician), pinned indicator, quoted-reply strip, images / voice notes / documents, timestamp; a tombstone for deleted-for-everyone.
- **Long-press actions:** Copy · Reply · Pin/Unpin · Delete for me · Delete for everyone (own turns).
- **Composer:** text, **attachments and voice notes**, reply bar; posts into the shared thread.

---

# Appendix — Route map

| Route | Screen |
|-------|--------|
| `/dietician/dashboard` | Dashboard — Tab 0 |
| `/dietician/patients` | Patients worklist — Tab 1 |
| `/dietician/profile` (+ `/edit`) | Profile hub — Tab 2 |
| `/dietician/patients/:id` | Patient detail (full clinical picture) |
| `/dietician/patients/:id/diet` | Diet plan editor |
| `/dietician/patients/:id/chat` | Dietician↔patient chat |

---

# Appendix — Legacy / unwired screens

For parity with the other panel docs: the dietician tree has **no dead screens** —
every file under `features/dietician/` is reachable from the 3 tabs or the 3
sub-screens above, and the router wires exactly one dietician dashboard
(`dietician_dashboard_screen.dart`). The app-wide legacy screens (the old patient
dashboard, glucose, track, care, appointments) belong to the patient tree — see
`PATIENT_PANEL_WORKFLOW.md`.

---

# Notes for a redesign

- **3 tabs, 3 sub-screens** — a small, focused surface.
- **The dietician's whole job is two acts:** write/send the **diet plan**, and **message** the patient — everything else is read-only context. Keep those two actions prominent (the persistent "Message patient" button and the diet-plan card already do this).
- **Shared components** with the other panels: `UserAvatar`, `ProfileSection`/`ProfileRow`, `ThemeSelector`, the chat bubbles + `CareComposer` + `JumpToLatest`, the lab-report row + `_AnalyteChip`, the diet-plan/food-log widgets. Restyling these touches the doctor and patient panels too — a consistency win, but review all three before shipping.
- **Copy fix worth doing:** two dashboard strings ("My Patients", "No patients on the clinic list yet") speak as if clinic-wide, but the dietician only sees assigned patients — align the wording.

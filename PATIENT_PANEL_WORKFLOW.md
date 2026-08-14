# ClinQ — Patient Panel: Full Workflow

A complete map of the patient side of the app: every bottom-nav tab, the sections
inside each, what each section does, and every sub-screen reachable from them.
Companion to `DOCTOR_PANEL_WORKFLOW.md`.

> **Scope:** the patient role. Colour palette lives in
> `mobile/lib/core/theme/app_colors.dart` (the "Clinical Precision" green system).

---

## 0. At a glance

The patient app is a **5-tab bottom navigation** shell (`app_shell.dart`), plus
deeper **sub-screens** pushed on top of the tabs.

| # | Tab | Icon | What it is | Route → screen |
|---|-----|------|-----------|----------------|
| 0 | **Home** | home | Read-only care dashboard (glucose, HbA1c, BP, diet, meds) | `/home` → `HomeScreen` |
| 1 | **Doctor** | chat bubble | The AI + clinic assistant chat ("Dr. Dey's Clinic") | `/chat` → `ChatScreen` |
| 2 | **Medicines** | pill | Prescriptions, schedule, reminders, dose logging | `/medications` → `MedicationsScreen` |
| 3 | **Dietician** | fork/knife | The **dietician chat** (photos here become food-log entries) | `/food-log` → `NutritionChatScreen` |
| 4 | **Profile** | person | Identity, settings, and the launcher for health/tests/etc. | `/profile` → `ProfileScreen` |

**Two things worth knowing up front:**
- The **Dietician tab is a chat, not a list.** A photo sent there *becomes* a food-log entry server-side. The old meal-log list still exists as a sub-screen (`/food-log/history`) pushed from inside the chat.
- **Adding a medicine = scanning a prescription.** Patients can't type medicines in; only the doctor prescribes. The patient scans the paper Rx and the server OCRs it into medicines with reminders.

```
Patient app
├── [Tab 0] Home ......... dashboard → "+ Add" glucose sheet · "View full plan" · "View all" food logs
├── [Tab 1] Doctor ....... AI/clinic chat (attachments, voice, citations, report-answer)
├── [Tab 2] Medicines .... hub:
│       ├── Scan Prescription (FAB — the only way to add meds)
│       ├── Dose history        (/medications/history)
│       ├── Prescriptions       (/medications/prescriptions)
│       ├── Reminder windows    (/medications/reminders)
│       └── Today's schedule → mark taken/skipped
├── [Tab 3] Dietician .... dietician chat → "Meal history" (/food-log/history)
└── [Tab 4] Profile ...... hub:
        ├── Appearance · Language · Glucose unit
        ├── Edit profile        (/profile/edit)
        ├── Health details      (/profile/health)
        ├── My tests & reports  (/profile/tests)
        ├── Notifications       (/profile/notifications)
        ├── Send feedback       (/profile/feedback)
        └── App lock · Call clinic · About · Log out
```

---

# TAB 0 — Home (care dashboard)

**File:** `home_screen.dart` · **Purpose:** a **read-only** snapshot of the
patient's care. Polls every 30s and on resume. The one place the patient *acts* is
logging a glucose reading.

| # | Section | What it shows / does |
|---|---------|---------------------|
| A | **Brand header** | ClinQ emblem + wordmark; avatar (tap → Profile) |
| B | **Name + Risk badge** | patient name; a risk pill only if the clinic set `showRisk` (red for critical/high, amber otherwise; low = none) |
| C | **Age / gender** | e.g. "54 y/o • Male" |
| D | **Fact grid** | up to 6 static cards, each shown only if data exists: **Condition**, **Next Visit** (follow-up date), **BMI / Wt / Ht**, **Blood Pressure** (red if high), **Food-log review** (cadence), **Last HbA1c** (red + "(High)" if high) |
| E | **Your glucose** | the one interactive card — **"+ Add"** and (with <2 readings) **"Add your first reading"** open the **log-glucose sheet**; with ≥2 readings it shows **Average / Lowest / Highest / Est. HbA1c** stats + a trend chart with the 70–180 target band |
| F | **Allergies & Intolerances** | red banner with a chip per allergen (only if any) |
| G | **Current Diet Plan** | goal + a grid of meal cards; **"View full plan"** opens a sheet with all meals, items, notes, and a "Best avoided" list (only if a plan exists) |
| H | **Current Medicines** | read-only list of active meds + schedule labels |
| I | **Recent Food Logs** | horizontal photo scroller; **"View All"** → the Dietician tab |

**Log-glucose sheet** (`log_glucose_sheet.dart`): value (mg/dL), context chips
(**Fasting / Pre-meal / Post-meal / Bedtime / Random**), date-time, notes →
**Save reading** (logs it, refreshes the trend, re-arms the check-in reminder).

---

# TAB 1 — Doctor (assistant chat)

**File:** `chat_screen.dart` · **Purpose:** one continuous AI + clinic assistant
thread. App-bar title **"Dr. Dey's Clinic"**. Polls every 3s.

**Sections / behaviour**
- **App bar:** title + a single **Call clinic** button (dials via the native dialer). No "new chat" — it's one ongoing conversation.
- **Error banner** — transient red strip, auto-clears.
- **Pinned banner** — tap to jump to the pinned message and cycle; close to unpin.
- **Message list** — bubbles with day separators + a "generating…" bubble while the AI replies.
  - **Empty state:** "How can I help today?" + 4 tappable suggestion cards (high sugar, breakfast ideas, numb feet, eye report) — tapping sends it.
  - **Per-message actions:** tap a **citation** to ask that topic · tap a reply-quote to jump · **Reply · Pin · Hide for me · Delete for everyone** (own messages) · **Retry** + **Report answer** (assistant messages).
- **Jump-to-latest** floating button when scrolled up.
- **Reply preview** strip when replying.
- **Composer:** **Attach** (camera / gallery / document, up to 5), text field ("Ask about your health…"), **Mic** (voice note), **Send**.

---

# TAB 2 — Medicines

**File:** `medications_screen.dart` · **Purpose:** the medication hub — schedule,
reminders, history, prescriptions, and dose logging. Polls every 30s and drives the
on-device reminder alarms.

| # | Section | What it does |
|---|---------|--------------|
| — | **FAB "Scan Prescription"** | the **only** way to add meds — OCRs a photo of the Rx into medicines with reminders |
| 1 | **Brand header** | logo + a **notifications bell** → Notifications settings |
| 2 | **Title** | "Medications" + subtitle |
| 3 | **Dose history** row | → `/medications/history` (taken & missed) |
| 4 | **Prescriptions** row | → `/medications/prescriptions` (view · share) |
| 5 | **Reminder windows** | Breakfast / Lunch / Dinner cards showing meal times; tap any → `/medications/reminders` |
| 6 | **Active prescriptions** | a card per active med: name, instructions, "ACTIVE", strength, plain-language schedule chip |
| 7 | **Today's schedule** | a tile per dose slot (time, med, meal relation, status **Taken/Skipped/Missed/Pending**); tapping a **Pending** slot opens the **mark-dose sheet** (Mark taken / Mark skipped + reason) — this feeds the adherence figure the doctor sees |

### Medicines sub-screens
- **Dose history** (`dose_history_screen.dart`, `/medications/history`) — period chips (7d / 2w / 30d), doses grouped by day with a "{taken}/{total}" header, each row status-coloured (Taken/Skipped/Missed) with med + time.
- **Prescriptions** (`prescriptions_screen.dart`, `/medications/prescriptions`) — cards (date, count, diagnosis, doctor); a detail sheet with **Open PDF** and **Share / Save**, and sections Complaint / Diagnosis / Medicines / Tests advised / Advice / Follow-up.
- **Reminder times** (`reminder_times_screen.dart`, `/medications/reminders`) — **Your meal times** (Breakfast/Lunch/Dinner pickers → Save re-arms alarms) and **Exact time per medicine** (tap a time chip to override a specific dose; stays fixed even if meal times change).

### Medicines modal flows
- **Scan prescription** (`scan_prescription_sheet.dart`) — choose (Take photo / From gallery) → "Reading your prescription…" → "Added N medicines" (reminders auto-set) or "Couldn't read that photo".
- **Mark dose** (`mark_dose_sheet.dart`) — **Mark taken** / **Mark skipped** (+ "Why are you skipping?" reason).
- **Reminder reliability** (`reminder_setup_sheet.dart`) — "Never miss a dose": grant exact-alarm + battery-optimisation exemptions so alarms fire when the phone sleeps.

---

# TAB 3 — Dietician (nutrition chat)

**File:** `nutrition_chat_screen.dart` · **Purpose:** the patient's chat with their
dietician. A photo sent here **also becomes a food-log entry** server-side (so a
meal isn't logged twice). Same triage runs on anything sent here as on the Doctor
thread.

**Sections / behaviour**
- **App bar:** two-line title **"Your dietician" / "Food and nutrition"**; a **"Meal history"** icon → `/food-log/history` (the meal-log list).
- **Thread** — dietician conversation; empty state "No messages yet"; per-message **Reply · Pin · Hide for me · Delete for everyone** (own).
- **Jump-to-latest** floating button.
- **Reply preview** strip.
- **Composer** (`care_composer.dart`): **Attach** (camera / gallery / document — a photo becomes a food log), text ("Message your dietician…"), **Mic** (voice), **Send**. If the server flags a message urgent → a red "the clinic has been alerted" snackbar.

### Dietician sub-screen
- **Food log / Meal history** (`food_log_screen.dart`, `/food-log/history`) — meal cards (photo, meal-type pill, timestamp, note); long-press to delete; **FAB "Log a meal"** opens a sheet (meal-type chips, note, add photo → **Save meal**).

---

# TAB 4 — Profile (settings hub)

**File:** `profile_screen.dart` · App-bar **"Profile"**.

| # | Section | Contents |
|---|---------|----------|
| 1 | **Header** | avatar (tap = change photo, long-press = fullscreen), name, phone, "Patient" pill |
| 2 | **Appearance** | Light / Dark / System toggle |
| 3 | **Language** | English / বাংলা / हिन्दी |
| 4 | **Preferences** | **Glucose unit** → picker sheet (mg/dL vs mmol/L) |
| 5 | **Account** | **Edit profile** · **Health details** · **My tests & reports** · **Notifications** · **Send feedback** |
| 6 | **Security** | **App lock** (biometric) |
| 7 | **Clinic** | **Call clinic** (tel:) · **About ClinQ** (version) |
| 8 | **Log out** | with confirmation |

### Profile sub-screens
- **Edit profile** (`edit_profile_screen.dart`, `/profile/edit`) — card-grouped form: Name, **Phone (locked — it's your login)**, Email, Date of birth, Gender, Address. Save button in the app bar.
- **Health details** (`health_details_screen.dart`, `/profile/health`) — Height, **Main concern** (chief complaint), Diagnosed-on, Allergies, and an **Emergency contact** (name / phone / relation). (Weight is deliberately excluded — it's a tracked vital, not a static field.)
- **My tests & reports** (`lab_tests_screen.dart`, `/profile/tests`) — **Advised by your doctor** (each with an Upload/Re-upload button) and **Uploaded reports** (thumbnail, date, delete, and the clinic's read-back analysis + "Flagged on the report" abnormals); **FAB "Upload report"** (PDF / Camera / Gallery).
- **Notifications** (`notifications_screen.dart`, `/profile/notifications`) — toggles: **Medicine reminders**, **Check-in reminders**, **Clinic alerts**, and a **Reminder reliability** row (opens the reliability sheet).
- **Send feedback** (`feedback_screen.dart`, `/profile/feedback`) — subject (**The clinic** / **This app**), optional 5-star rating, message → **Send** → thank-you.

---

# Appendix — Route map

| Route | Screen |
|-------|--------|
| `/home` | Home (dashboard) — Tab 0 |
| `/chat` | Doctor (assistant chat) — Tab 1 |
| `/medications` | Medicines hub — Tab 2 |
| `/medications/history` | Dose history |
| `/medications/prescriptions` | Prescriptions (view/share PDF) |
| `/medications/reminders` | Reminder times (meal times + per-med overrides) |
| `/food-log` | Dietician chat — Tab 3 |
| `/food-log/history` | Food log / meal history |
| `/profile` (+ tab) | Profile hub — Tab 4 |
| `/profile/edit` | Edit profile |
| `/profile/health` | Health details |
| `/profile/tests` | My tests & reports (lab uploads) |
| `/profile/notifications` | Notification settings |
| `/profile/feedback` | Send feedback |

*(Glucose logging is a modal sheet from Home, not a route.)*

---

# Notes for a redesign

- **5 tabs, ~11 sub-screens.** The redesign surface is the 5 tab screens + these sub-screens.
- **Highest-traffic screens:** Home dashboard, Doctor chat, Medicines hub — restyle these first.
- **Shared components** already reused across patient + doctor: `ProfileSection`/`ProfileRow`, `UserAvatar`, the chat bubbles + composers, `JumpToLatest`, the lab-report row, the sparkline. Restyling these propagates to both panels — a benefit, but review both sides before shipping.
- **Legacy / unwired** (present in the tree but unreachable in the patient panel today — don't redesign these): the old patient `DashboardScreen` (`features/dashboard/`, replaced by `HomeScreen` + care summary), `TrackScreen`, `GlucoseScreen`, `CareScreen`/`CarePlaceholderScreen`, `MyAppointmentsScreen`/`BookAppointmentScreen`. The appointment feature is intentionally gone.

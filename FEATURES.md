# ClinQ — Feature List by Panel

Every screen the app ships, grouped by the panel it belongs to and the tab or
section it sits under. Three panels share one codebase and one backend; which
one you land in is decided by your account role at login.

| Panel | Role | Landing screen |
| --- | --- | --- |
| Patient | `patient` | Assistant tab (`/chat`) |
| Doctor / clinic staff | `doctor`, `staff` | Home (`/clinician/dashboard`) |
| Dietician | `dietician` | Dashboard (`/dietician/dashboard`) |

---

## Shared — before you are signed in

| Screen | What it does |
| --- | --- |
| **Splash** | Restores the saved session and routes you to the right panel. |
| **Language picker** | English · বাংলা · हिन्दी. Each option is written in its own script, so a Hindi speaker can find "हिन्दी" while the app is still in English. |
| **Login** | Phone + password. `+91` is fixed; the field takes 10 digits and rejects anything that does not start 6–9. |
| **Register** | Patient self-signup: name, phone, password, date of birth, gender. Validated field by field with the message under the field it belongs to. |
| **App lock** | If enabled, a full-screen unlock gate stands in front of everything — device PIN or biometric. |

Also shared by all three panels: light/dark/system theme, three languages, an
offline banner, and push notifications through Firebase Cloud Messaging.

---

## Patient panel

Four tabs: **Assistant · Medicines · Food · Profile**.

### Tab 1 — Assistant (`/chat`)

One thread. The AI assistant, Dr. Dey and the dietician all speak in it, each
labelled with who is talking — a patient never has to guess who replied.

**Talking to the clinic**
- Ask anything in the thread; the assistant answers from the clinic's own
  protocols (retrieval over the knowledge base), not from generic web advice.
- Scoped to endocrinology and diabetology. Outside that scope it says so and
  hands off rather than guessing.
- Doctor and dietician replies land in the same thread, in real time.
- Typing indicator while the assistant is composing; no empty bubble flash.

**Voice messages**
- Hold-free tap-to-record with a live waveform that follows your actual volume.
- Up to 10 minutes per note. AAC-LC, small enough to send on a weak connection.
- The server transcribes it, so the assistant can answer a spoken question and
  the triage rules can read it.
- Both sides can play any voice note back, scrub, and see its length.

**Attachments**
- Photo from camera or gallery; PDF, Word, Excel and text documents.
- Images are compressed before upload.

**In the thread**
- Reply to a specific message (quoted above the input box).
- Pinned messages stay reachable at the top — prescriptions and instructions
  the clinic wants you to keep.
- Report a reply for clinical review (`Thank you, this reply has been reported`).
- Date separators (Today / Yesterday / the date), delivery ticks and a
  "seen by the clinic" mark.
- Jump-to-latest button when you have scrolled up.
- Call the clinic from the header — the clinic's number, never the doctor's
  personal line.

**Safety**
- Every message runs through a deterministic triage engine first. Rules decide
  urgency; the model may raise it, never lower it.
- An emergency answer shows the emergency card and calls the clinic's number.
- Anything urgent or emergency raises a clinical alert on the doctor's side at
  the same moment.

### Tab 2 — Medicines (`/medications`)

- Current medicines with dose, timing and how long to keep taking them.
- **Scan prescription** — photograph a paper prescription and the app reads the
  medicines off it; you confirm before anything is saved.
- **Reminder times** (`/medications/reminders`) — set your own breakfast, lunch
  and dinner times so "after breakfast" means your breakfast.
- Local reminder notifications at those times.

### Tab 3 — Food (`/food-log`)

- **Log a meal** — what you ate, when, and an optional photo.
- Day-by-day history.
- The dietician sees this log and reviews it on a set interval.
- The diet plan they write for you arrives in your Assistant thread, so it sits
  with everything else the clinic has told you rather than in a second inbox.

### Tab 4 — Profile (`/profile`)

| Section | Rows |
| --- | --- |
| **Header** | Photo (tap to change), name, phone. |
| **Appearance** | Light · Dark · System. |
| **Language** | English · বাংলা · हिन्दी. |
| **Preferences** | Glucose unit — mg/dL or mmol/L, applied everywhere numbers are shown. |
| **Account** | Edit profile · Health details · My tests & reports · Notifications · **Send feedback**. |
| **Security** | App lock on/off (device PIN or biometric). |
| **Clinic** | Call the clinic · About (with version). |
| | Log out. |

**Account rows in detail**
- **Edit profile** (`/profile/edit`) — name, photo, date of birth, gender.
- **Health details** (`/profile/health`) — diabetes type, diagnosis year,
  height, weight, allergies, other conditions. This is what the assistant reads
  before it answers, so it is worth filling in.
- **My tests & reports** (`/profile/tests`) — lab tests the doctor advised, and
  the reports you have uploaded against them.
- **Notifications** (`/profile/notifications`) — per-category switches.
- **Send feedback** (`/profile/feedback`) — *new*. Pick a subject: **the clinic**
  (your care, appointments, staff) or **this app** (bugs, speed, anything
  confusing). Optional 1–5 star rating, and a message of up to 2000 characters.
  The rating is optional on purpose — someone with something specific to say
  should not have to reduce it to a number first. The screen states plainly
  that your name is sent with it so the clinic can follow up, and that it is
  not part of your medical record. Feedback never enters the clinical alert
  queue: "the app is slow" and "I have chest pain" must not share a list.

---

## Doctor panel (doctor + clinic staff)

Three tabs: **Home · Patients · Profile**.

### Tab 1 — Home (`/clinician/dashboard`)

The clinic's pulse, top to bottom:

| Section | What it shows |
| --- | --- |
| **Headline counts** | Total patients · Pending summaries · Active today. |
| **Priority strip** | High priority · New messages · Vitals warning. |
| **Active alerts** | Live clinical alerts, worst first, tap to open the patient. |
| **Clinic pulse** | Activity over the recent period. |
| **Needs attention** | Patients who have gone quiet or drifted out of range. "All caught up" when there is nothing. |
| **Nutrition** | Food-log reviews that are due. |

### Tab 2 — Patients (`/clinician/patients`)

A true inbox, not a directory:
- One row per patient, newest conversation at the top.
- Last message preview, its timestamp, and an unread badge.
- Patient photo on the row, pulled live.
- Search by name or phone.
- Polls every few seconds so new messages appear without a manual refresh.

**Patient conversation** (`/clinician/patients/:id/thread`)
- The patient's full thread — their messages, the assistant's answers and the
  dietician's notes, in one place. The doctor's own replies sit on the right,
  everything received on the left.
- Reply as the doctor; the patient sees it attributed to Dr. Dey.
- **Send a voice message** — when the doctor is between patients it is faster to
  speak than to type.
- Long voice notes from a patient collapse to one line of transcript with
  *Show more*, so a 10-minute note does not bury the thread. The doctor can read
  it or play it, whichever is quicker.
- Attach a photo, a document (PDF, Word, Excel, text) or take a picture.
- Jump-to-latest button.
- Call the patient from the header.

**Patient record** (`/clinician/patients/:id`)
- Header: name, age, sex, risk band, contact — with **Call** and **Message**.
- **HbA1c history** — the trend, not just the last value.
- **Test reports** — what was advised and what has come back.
- **Recent alerts** — this patient's alert history.
- **Assistant context** — exactly what the AI was given before it answered, so
  the doctor can audit any reply.
- **Assign dietician** — pick an existing dietician or **add a new dietician**
  (name, 10-digit mobile, password, all validated), and set how often the food
  log should be reviewed. Unassign from the same sheet.
- **Prescribe** (`/clinician/patients/:id/prescribe`) — medicines with dose,
  timing and duration; lab tests advised; diagnosis; general advice; follow-up
  date. Sending it delivers it into the patient's thread and their Medicines tab
  in one step.

### Tab 3 — Profile (`/clinician/more`)

| Section | Rows |
| --- | --- |
| **Header** | Photo (tap to change), name, role. |
| **Appearance** | Light · Dark · System. |
| **Language** | English · বাংলা · हिन्दी. |
| **Account** | Edit profile. |
| **Clinic tools** | Clinical alerts · Chat review · Knowledge base · **Patient feedback**. |
| **Security** | App lock. |
| **App** | Clinic phone number · About. |
| | Log out. |

**Clinic tools in detail**
- **Clinical alerts** (`/clinician/alerts`) — the triage queue, filtered by Open
  / Acknowledged / Resolved / All. Acknowledge or resolve each one. Emergency
  and urgent alerts also push to the clinic's phones; nothing below that does,
  so the ones that push stay meaningful.
- **Chat review** (`/clinician/chat-review`) — every assistant reply a patient
  reported, with the full exchange, so a wrong answer can be corrected at the
  source.
- **Knowledge base** (`/clinician/knowledge`) — the clinic's own protocols, in
  the doctor's words. Add, edit and remove entries; each is embedded and becomes
  what the assistant retrieves from. This is the difference between the
  assistant answering as Dr. Dey's clinic and answering as a generic chatbot.
- **Patient feedback** (`/clinician/feedback`) — *new*. Everything patients sent
  from their profile, newest first, filterable by **All / The clinic / The app**.
  Each card shows the subject, the star rating, the message, who wrote it and
  when, with **Mark reviewed**. Unreviewed cards carry a coloured border.
- **Clinic phone number** — the number every "call the clinic" button dials.
- **Appointments** (`/clinician/appointments`) and **Clinics**
  (`/clinician/clinics`) exist as routes for schedule and location management.

---

## Dietician panel

Two tabs: **Dashboard · Patients**. Two, not three — the dashboard says what
needs doing today and the patient list is everyone; anything more would be
navigation for its own sake.

### Tab 1 — Dashboard (`/dietician/dashboard`)

The dietician's day, ordered by what is actionable rather than what looks
impressive. Counts and lists come from a single endpoint, so a number never
disagrees with the list under it.

| Section | What it shows |
| --- | --- |
| **Counts** | My patients · Reviews due · Plans to send. The last two turn amber and orange when they are not zero. |
| **Reviews due** | Patients whose food-log review interval has elapsed, each with how long it has been — *"12 days ago"*, or *"Never reviewed"*. Tap to open them. |
| **Waiting for a diet plan** | Patients with no plan, or a plan that was written but never sent. A plan the patient has not received is still work outstanding. |
| **All caught up** | Shown only when *both* worklists are genuinely empty. A green tick over outstanding work is worse than no tick. |
| **Latest meals logged** | The most recent meals across all assigned patients, with the photo, the patient's name and the time. Tap to open that patient. |

### Tab 2 — My patients (`/dietician/patients`)

- Only patients a doctor has assigned to this dietician. The backend enforces
  it; an unassigned patient is not reachable even by URL.
- One card per patient, sorted with the overdue ones first.
- A **Review due** badge when the food-log review interval has elapsed.
- Header shows who is signed in; log out from the app bar.
- Empty state: *"A doctor will assign patients to you."*

### Patient overview (`/dietician/patients/:id`)

| Section | What it shows |
| --- | --- |
| **Header** | Name, age, sex, risk band. |
| **Facts** | Diabetes type, height, weight, and the review interval in days. |
| **Allergies** | Called out separately — the one thing a diet plan must not get wrong. |
| **Diet plan** | The plan summary card (below). Sits above everything else: the plan is what the dietician is here to produce, and the rest of the screen is input to it. |
| **Current medicines** | With a count, so a plan is built around what the patient is actually taking. |
| **Food log** | The patient's meals, with photos, day by day. |
| | **Message patient** — opens the nutrition chat. |

### Diet plan (`/dietician/patients/:id/diet`)

Chat guidance is easy to write and easy to lose — two hundred messages later,
*"so what am I supposed to eat at breakfast?"* has no answer the patient can
find. The plan is the durable form of the same advice: one document per patient,
edited in place, always current. Never auto-generated — the assistant may
explain a plan the dietician wrote, but prescribing what a diabetic eats is a
clinical act.

**On the patient screen**, a summary card shows the goal, a chip per meal with
its time, how many foods are on the avoid list, and — the part that matters
most — whether the patient has actually been sent it: *Not sent yet*, *Edited
since it was last sent* (amber border), or *Sent 4 Aug · Ritu Sen*. A
finished-looking plan the patient has never seen is a draft, and the card says
so instead of looking done.

**In the editor:**

| Field | Notes |
| --- | --- |
| **Goal** | What the plan is for, in the patient's terms — *"bring fasting sugar under 130 without cutting rice completely"*. |
| **Meals** | Add as many as the day needs. Suggested chips (Breakfast, Mid-morning, Lunch, Evening snack, Dinner) get the first plan started in a few taps, plus **Other** for anything else. Meal name and time are free text on purpose: an Indian day is not breakfast/lunch/dinner, and *"before namaz"* has to be sayable. |
| **Items** | One line per item, each separately editable — fixing *"2 rotis"* does not mean retyping the meal. Plus an optional note per meal. |
| **Best avoided** | Chips, kept out of the meal cards deliberately: a patient scanning for *"can I have this?"* should have one place to look. |
| **Anything else** | Water, cooking oil, eating out, fasting days. |

**Save** and **Send to patient** are separate buttons. A dietician halfway
through moving a portion from lunch to dinner should not be notifying the
patient twice. Sending pushes the plan into the patient's care thread as
readable plain text — headings, bullets, and a closing line inviting them to say
if something does not suit them. Plain text rather than a custom card so it
survives translation, can be copied, and still makes sense if the patient
screenshots it for whoever does the cooking at home. Sending also marks the
food-log review done for that cycle and notifies the patient. If there are
unsaved edits on screen, they are saved first — the plan the patient receives is
always the one the dietician is looking at.

### Nutrition chat (`/dietician/patients/:id/chat`)

- Writes into the same care thread the patient already uses, tagged as the
  dietician — the patient does not learn a second inbox.
- Sees the conversation history, including attachments.
- Empty state: *"Say hello and share your first food guidance."*

---

## Cross-cutting

**Notifications.** Deliberately narrow. The doctor is pushed for emergency and
urgent clinical alerts, appointment changes, and an evening digest — not for
every message. If every message buzzed, the emergency buzz would be the one
that gets ignored. Patients are pushed for medicine reminders and for emergency
alerts raised on their own account.

**The assistant's boundaries.** Rule-based triage runs before the model and
cannot be overridden downward. The assistant never diagnoses, never changes a
prescription, and never claims to be the doctor. Every AI reply is labelled as
the assistant, and any patient can report one for review.

**Privacy.** Feedback is attributable and kept out of the medical record.
Clinical data is scoped by role: a dietician sees only assigned patients, a
patient sees only themselves.

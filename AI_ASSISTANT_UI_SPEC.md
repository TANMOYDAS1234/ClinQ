# ClinQ — AI Assistant UI Specification

Design spec for redesigning the AI Health Assistant (Chat) screen: voice input, Gemini-style
motion, WhatsApp-style voice notes, and a general visual lift.

Scope: `mobile/lib/features/chat/`. Target: Flutter 3.41, Material 3, Android + iOS.

---

## 1. Two constraints that must shape every decision

### 1.1 The triage engine only reads text

Every patient message is classified by a deterministic rule engine
(`backend/src/services/triage/`) **before** Gemini is called. It matches multilingual regex
patterns against the message *text*. Blood sugar > 400, chest pain, breathing difficulty,
sudden vision loss, stroke signs, self-harm — all detected from text, in English, Bengali and
Hindi.

**Therefore: audio must be transcribed on-device and sent as text.** If raw audio were uploaded
and transcribed server-side after triage, or transcribed by Gemini alone, a patient saying
*"আমার বুকে ব্যথা হচ্ছে"* (I am having chest pain) would not raise an alert. Emergency detection
would silently break for every voice user.

This is not a preference. It is the single hard requirement of the voice feature.

### 1.2 The backend accepts no audio

`backend/src/routes/uploads.js` allows only:

```js
const ALLOWED_MIME = new Set([
  'image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf'
]);
```

`kind` is `foot_photo | retinal_report | lab_report | prescription_pdf | meal_photo | other`.

There is no audio MIME type and no audio `kind`. Storing voice notes would require backend
changes, object storage, retention policy, and — because a voice note is patient health
information — an audit and consent story.

**Recommendation: ship on-device speech-to-text first.** It needs zero backend change, keeps
triage safe, and delivers the feature patients actually want (speaking instead of typing). Treat
stored voice notes as a separate, later decision — see §7.

---

## 2. Who this is for

Patients of a diabetology clinic in Kolkata. Design implications, not decoration:

- **Older adults are the majority.** Type 2 diabetes skews 45+. Presbyopia and reduced fine motor
  control are the norm, not the edge case.
- **Three scripts.** Latin, Bengali (বাংলা), Devanagari (हिन्दी). Bengali and Devanagari have
  taller glyph stacks than Latin — conjuncts and diacritics need vertical room.
- **Typing is genuinely hard** in Bengali and Hindi on a phone keyboard. This is the real reason
  voice matters here: it is an accessibility feature, not a novelty.
- **Some users are unwell while using this.** The interface may be read by someone with blurred
  vision from high blood sugar, or shaking from hypoglycaemia.

Consequences: minimum body text **16sp**, minimum tap target **48dp** (raised from the current
44), line-height **1.5** for Bengali/Devanagari, and no interaction that depends on a precise
gesture.

---

## 3. Design tokens

Existing values from `mobile/lib/core/theme/app_colors.dart` — do not invent new brand colours.

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#0F766E` | `#14B8A6` | User bubble, send button, active mic |
| `surface` | `#F8FAFC` | `#0F1720` | Screen background |
| `danger` | `#DC2626` | `#DC2626` | Emergency card, recording indicator |
| `dangerBg` | `#FEE2E2` | `#3F1414` | Emergency card fill |
| `warning` | `#D97706` | `#D97706` | Urgent card |
| `warningBg` | `#FEF3C7` | `#3A2A0A` | Urgent card fill |
| `success` | `#059669` | `#059669` | Routine status |

**Typography:** no custom `fontFamily`. The platform default carries full Bengali and Devanagari
coverage; a webfont almost certainly will not. Body 16sp, assistant message body 17sp,
line-height 1.5, timestamps 13sp.

**Radii:** bubbles 20dp, with a 4dp "tail" corner on the sender's side. Cards 16dp. Composer
pill 28dp.

**Elevation:** none on bubbles. Use a 1dp `outlineVariant` border instead — shadows muddy in dark
mode and add nothing at these sizes.

---

## 4. Screen anatomy

```
┌─────────────────────────────────────┐
│ ☰   AI Assistant            ⊕ new   │  App bar
├─────────────────────────────────────┤
│                                     │
│  ┌────────────────────────┐         │  Assistant bubble
│  │ Your sugar of 210 is…  │         │  17sp, surfaceContainerLow
│  └────────────────────────┘         │
│   [ ADA 2025 §6 ] [ IDF ]           │  Citation chips
│   AI-assisted guidance, not a       │  Disclaimer — 13sp italic
│   diagnosis                    ⚑    │  Flag affordance
│                                     │
│              ┌──────────────────┐   │  User bubble
│              │ my sugar is 210  │   │  primary fill, white text
│              └──────────────────┘   │
│                                     │
│  ╔═════════════════════════════╗    │  EMERGENCY — never a bubble
│  ║ ⚠  Go to the nearest        ║    │  danger border, dangerBg fill
│  ║    hospital immediately     ║    │
│  ║    [ 📞 Call clinic ]       ║    │  tel: launcher
│  ╚═════════════════════════════╝    │
│                                     │
├─────────────────────────────────────┤
│ ( 📎 )  Ask about your health   🎤  │  Composer — mic when empty
└─────────────────────────────────────┘  send when text present
```

### 4.1 What must not change

`chat_message_bubble.dart` routes `urgency == 'emergency'` and `'urgent'` messages into dedicated
cards instead of bubbles. **This is a safety mechanism, not a style choice.** A redesign may
restyle those cards but must not fold them back into ordinary bubbles, must not reduce their
contrast, and must not push the "Call clinic" button below the fold.

The emergency card must remain the loudest thing on the screen. If a visual refresh makes it
prettier but quieter, the refresh is wrong.

Equally fixed:
- The disclaimer under every assistant message.
- The flag ⚑ affordance on every assistant message.
- Citation chips whenever `citations` is non-empty.

---

## 5. The mic — Gemini-style

### 5.1 Behaviour

Tap the mic → full-width listening sheet slides up over the composer. On-device speech
recognition streams partial results into a live transcript. Tap done (or 2s of silence) →
transcript drops into the composer as **editable text**, not sent automatically.

**Never auto-send a transcription.** Speech-to-text mishears numbers constantly, and in this app
a number is a blood sugar reading. "One forty" becoming "one four zero" is harmless; "forty"
becoming "four hundred" is an emergency alert that should not have fired — or worse, the reverse.
The patient must see and confirm the text.

Show a language chip on the sheet (`বাংলা ▾`) defaulting to the user's app language, because the
recognizer needs an explicit locale (`bn-IN`, `hi-IN`, `en-IN`) and will produce garbage if it
guesses wrong.

### 5.2 The listening animation

Gemini's mic uses a **morphing gradient orb** rather than a classic waveform. Reproduce that
feeling:

- A circle, 96dp, filled with a 3-stop sweep gradient — `#0F766E → #14B8A6 → #5EEAD4`.
- The gradient rotates continuously, **4000ms per revolution, linear**, never stopping.
- Two blurred blobs inside drift on independent sine paths (3200ms and 4700ms, deliberately
  coprime so the pattern never visibly repeats).
- The whole orb **scales with microphone amplitude**: map RMS to `1.0 → 1.18` with a 120ms
  ease-out follow, so it breathes with the voice rather than jittering per-frame.
- A soft outer glow at 24% opacity scales with it, 1.4× the orb radius.

Below the orb, four amplitude bars (4dp wide, 3dp radius, 8–40dp tall) as a secondary read for
users who find the orb ambiguous. Bars respond faster than the orb — 60ms.

**Reduced motion:** if `MediaQuery.disableAnimations` is true, replace the entire orb with a
static circle and a single pulsing 1.0→1.06 scale at 1200ms. Vestibular sensitivity is common in
this age group.

### 5.3 States

| State | Orb | Caption |
|---|---|---|
| Idle | not shown | — |
| Listening | rotating gradient, amplitude-scaled | "Listening…" + live transcript |
| No speech detected | slows to 8000ms, desaturates 40% | "I didn't catch that — try again" |
| Permission denied | not shown | "Microphone access is needed" + Settings button |
| Unavailable | not shown | "Voice input isn't available on this device" |

Every state needs its Bengali and Hindi string. A failure message in English defeats the purpose
for the users who need voice most.

---

## 6. The message border animation

Gemini sweeps a gradient along the border of the response while generating. Apply it to the
**assistant bubble while awaiting `POST /chat/message`**, replacing the current three-dot
`TypingIndicator`.

- A skeleton bubble, ~60% width, at the assistant's alignment.
- **1.5dp border** painted with a sweep gradient: `transparent → #14B8A6 → #5EEAD4 → transparent`,
  the visible arc covering ~35% of the perimeter.
- Rotates **1800ms per revolution, `Curves.linear`**. Any easing makes it look like it is
  stuttering.
- Bubble fill stays flat `surfaceContainerLow`; only the border moves.
- Three shimmer lines inside (14dp tall, 7dp radius) at 90%/75%/40% width, shimmering left-to-right
  at 1400ms with a 400ms stagger.

The response takes 3–8 seconds in practice — the smoke test measured 7.4s for a triage-heavy
message. That is long enough that a static spinner feels broken, which is exactly what this
solves.

**On arrival:** the border sweep completes its current revolution rather than cutting mid-arc, the
shimmer cross-fades to real text over 220ms `Curves.easeOut`, and the bubble grows to its true
height over 260ms `Curves.easeOutCubic`.

**Never** apply the sweep to an emergency or urgent card. Those must appear instantly at full
contrast — decoration on a myocardial infarction warning is indefensible.

---

## 7. Voice notes — WhatsApp-style

Wanted, but this is the part with real cost. Read §1.2 first.

### 7.1 What is cheap and safe

The **interaction pattern** costs nothing and is worth copying immediately:

- **Press and hold** the mic to record; release to finish.
- **Slide left to cancel** — a trash icon and "◀ slide to cancel" appear.
- **Slide up to lock** — hands-free recording, mic becomes a stop button.
- Live waveform + `0:07` elapsed timer while recording.
- Haptic on start, on lock, on cancel.

Applied to *transcription*, this gives the WhatsApp feel with none of the storage, retention, or
compliance burden. Hold to speak, release, see your words in the composer.

### 7.2 What stored voice notes actually cost

If the clinic wants the patient's actual voice retained in the transcript:

| Requirement | Detail |
|---|---|
| Backend | Add `audio/mp4`, `audio/aac`, `audio/ogg` to `ALLOWED_MIME`; add `voice_note` kind |
| Storage | Audio is far larger than text; needs object storage, not the local `uploads/` dir |
| Retention | Voice is PHI under DPDP. Needs a defined retention window and deletion path |
| Consent | Recording a patient's voice needs explicit, separate, auditable consent |
| Playback | Waveform scrubber, 1x/1.5x/2x speed, resume-from-position, earpiece proximity |
| **Triage** | **Still must transcribe on-device before sending** — the rules read text |

Note the last row. Even with stored audio, transcription is not optional. The audio becomes an
*attachment to* a text message, never a replacement for it.

**Recommendation:** ship §7.1 now. Defer §7.2 until someone owns the retention and consent
questions.

---

## 8. Composer

Single pill, 28dp radius, `surfaceContainerHigh` fill, 1dp `outlineVariant` border.

| Element | Behaviour |
|---|---|
| 📎 Attach | Left, 48dp. Existing image upload — photos of meals, meters, reports |
| Text field | Grows 1→5 lines. 16sp. Hint localized |
| 🎤 / ➤ | Right, 48dp. Mic when empty; **cross-fades** to send when text present, 180ms `easeOut` |

The mic↔send cross-fade should scale 0.8→1.0 as it fades, not just swap icons. It is the single
most-used control on the screen and deserves the polish.

**While sending:** field stays editable — do not lock a patient out of typing while waiting. Send
button becomes a 22dp indeterminate progress ring.

---

## 9. Empty state

The current welcome is a generic icon and two lines. Replace with **suggestion chips** that teach
the assistant's actual capabilities, localized, one tap to send:

- "My sugar is 250 — what should I do?"
- "What can I eat for breakfast?"
- "Why do my feet feel numb?"
- "Explain my last eye report"

Four maximum. These double as a safety demonstration: the first one visibly triggers real
guidance, which teaches patients this is worth using when something is wrong.

---

## 10. Motion summary

| Element | Duration | Curve |
|---|---|---|
| Mic orb rotation | 4000ms | linear, infinite |
| Mic orb amplitude follow | 120ms | easeOut |
| Amplitude bars | 60ms | easeOut |
| Bubble border sweep | 1800ms | linear, infinite |
| Shimmer | 1400ms, 400ms stagger | easeInOut |
| Response cross-fade | 220ms | easeOut |
| Bubble height grow | 260ms | easeOutCubic |
| Mic ↔ send | 180ms | easeOut |
| New message entry | 240ms | easeOutCubic, 8dp slide up |
| Listening sheet | 280ms | easeOutCubic |

Nothing exceeds 300ms except deliberate infinite loops. Every infinite animation must stop when
the screen loses focus — a rotating gradient burning battery in the background is a bug.

---

## 11. Accessibility

- Minimum tap target **48dp** (current code uses 44).
- Text scales to **200%** without clipping. Test in Bengali, where strings are longest.
- Contrast **4.5:1** minimum; emergency card **7:1**.
- Every animated element has a semantic label. The orb announces "Listening" — an animation with
  no label is invisible to a screen reader.
- Recording state announced via `SemanticsService.announce`.
- **Colour is never the only signal.** The emergency card carries an icon and explicit text, not
  just red. Roughly 8% of men have colour vision deficiency, and this cohort is mostly men over 45.
- Respect `MediaQuery.disableAnimations` everywhere.

---

## 12. Implementation notes

**Packages** (none currently in `pubspec.yaml`):

| Need | Package | Note |
|---|---|---|
| Speech-to-text | `speech_to_text` | On-device, supports `bn-IN` / `hi-IN` / `en-IN` |
| Recording (if §7.2) | `record` | Only if storing audio |
| Playback (if §7.2) | `just_audio` | Only if storing audio |
| Haptics | `flutter/services` | Built in — `HapticFeedback` |

**Permissions:** `RECORD_AUDIO` in `AndroidManifest.xml`, `NSMicrophoneUsageDescription` and
`NSSpeechRecognitionUsageDescription` in `Info.plist`. iOS rejects builds whose usage strings do
not explain the purpose — "ClinQ uses the microphone so you can speak to the health assistant
instead of typing."

**Files to touch:**

```
chat/presentation/widgets/
  chat_composer.dart         mic button, cross-fade
  typing_indicator.dart      → replace with animated-border skeleton
  voice_input_sheet.dart     new — orb, transcript, language chip
  animated_border_bubble.dart new — sweep gradient painter
  chat_message_bubble.dart   restyle only; routing logic unchanged
  emergency_card.dart        restyle only; must stay loudest
```

**Do not touch:** `chat_controller.dart`, `chat_repository.dart`, or anything under
`backend/src/services/triage/`. This is a presentation-layer change.

---

## 13. Acceptance criteria

- [ ] Voice input produces **editable text** in the composer; never auto-sends
- [ ] Transcription works in en / bn / hi with an explicit locale selector
- [ ] A transcribed "chest pain" in any of the three languages still raises the emergency alert
- [ ] Emergency and urgent cards render instantly, unanimated, at full contrast
- [ ] Border sweep and shimmer replace the dot indicator during generation
- [ ] Mic ↔ send cross-fades on text entry
- [ ] All animations disabled under `MediaQuery.disableAnimations`
- [ ] Every new string localized in en / bn / hi
- [ ] 200% text scale, no clipping, verified in Bengali
- [ ] All tap targets ≥ 48dp
- [ ] Animations stop when the screen is backgrounded
- [ ] `flutter analyze` clean; existing chat tests still pass

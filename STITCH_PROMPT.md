# Stitch Prompts — ClinQ AI Assistant

Prompts for [Google Stitch](https://stitch.withgoogle.com) to design the AI Health Assistant screen.

**How to use:** Stitch does better with one screen per prompt than one prompt describing five
screens. Run **Prompt 1** first to establish the visual language, then use *"Edit this screen"* or
a new prompt in the same project for 2–5 so they inherit the style.

Stitch renders static screens — it will not animate. Prompt 6 gets you the *frames* of each
animation; the timings live in [AI_ASSISTANT_UI_SPEC.md](AI_ASSISTANT_UI_SPEC.md) §10.

---

## Prompt 1 — Main chat screen (run this first)

```
Design a mobile AI health assistant chat screen for a diabetes care app used by patients
of an Indian physician. The users are mostly adults over 45, so text is large and touch
targets are generous.

Style: calm, clinical, trustworthy — a medical product, not a consumer chatbot. Deep teal
#0F766E as the primary colour, near-white #F8FAFC background, soft neutral greys. Rounded
20px message bubbles with no drop shadows, using thin 1px borders instead. Generous
whitespace. Clean sans-serif, 17px body text, 1.5 line height.

Layout top to bottom:
- Slim app bar: hamburger menu on the left, title "AI Assistant", a "new chat" plus icon
  on the right.
- Scrolling conversation:
  - Assistant messages on the left in light grey bubbles with a small square bottom-left
    corner. Under each: two small rounded source chips reading "ADA 2025 §6" and
    "IDF Guidelines", then a 13px italic grey line "AI-assisted guidance, not a diagnosis"
    with a small outline flag icon at the end.
  - Patient messages on the right in solid teal #0F766E bubbles with white text and a small
    square bottom-right corner.
  - One prominent alert card, full width, replacing a normal bubble: soft red #FEE2E2 fill,
    2px solid red #DC2626 border, 16px radius, a warning triangle icon, bold heading
    "Go to the nearest hospital immediately", a line of body text, and a full-width white
    button with a phone icon reading "Call clinic". This card must be the loudest, highest
    contrast element on the entire screen.
- Bottom composer: a single rounded pill, 28px radius, with a paperclip icon on the left,
  placeholder text "Ask about your health", and a circular teal microphone button on the
  right.

Show a realistic conversation: patient asks "my sugar is 250 after lunch", assistant
replies with guidance, patient says "I also have chest pain", and the red emergency card
follows.

Include both light and dark versions. Dark mode uses #0F1720 background and #14B8A6 teal.
```

---

## Prompt 2 — Voice input / listening sheet

```
Design a voice input screen for the same medical chat app, matching the existing style.

A bottom sheet covers the lower two-thirds of the screen with a 28px top radius, dimming
the conversation behind it.

Centre of the sheet: a large glowing circular orb, 96px, filled with a smooth rotating
gradient flowing from deep teal #0F766E through #14B8A6 to pale mint #5EEAD4. Two soft
blurred highlights drift inside it. A wide diffuse glow surrounds the orb at low opacity,
as though it is lit from within. It should feel alive and breathing, not like a loading
spinner.

Below the orb: four short rounded vertical bars of varying heights in teal, like a small
audio level meter.

Below that: the word "Listening…" in medium grey, and beneath it live transcribed text in
large 20px dark type reading "my blood sugar is two hundred and fifty after lunch" — with
the last few words slightly lighter, as if still being recognised.

Top-right of the sheet: a small rounded pill chip reading "English ▾" for choosing the
speech language.

Bottom of the sheet: a wide teal "Done" button and a plain grey "Cancel" text button.

Also produce three variants of this sheet:
1. Error state — orb desaturated and dimmed, caption "I didn't catch that — try again"
2. Permission state — no orb, a microphone-off icon, "Microphone access is needed", and an
   "Open settings" button
3. The same sheet with Bengali text: chip reads "বাংলা ▾", caption "শুনছি…"
```

---

## Prompt 3 — Assistant generating a reply

```
Design the loading state of the same medical chat screen, shown while the AI is composing
a reply.

At the assistant's position on the left, show a placeholder bubble about 60% of the screen
width. The bubble's outline is a thin 1.5px animated-looking gradient border — a bright
mint-to-teal arc covering roughly a third of the perimeter, fading to transparent at both
ends, as if a light is travelling around the edge of the bubble. The bubble fill stays flat
light grey.

Inside the bubble: three rounded placeholder lines at 90%, 75% and 40% width, in a slightly
lighter grey with a soft left-to-right shimmer highlight.

The rest of the conversation above is fully rendered and normal. The composer at the bottom
shows its send button replaced by a small circular progress ring.

Show three frames of this so the travelling border light appears at different points around
the bubble — top-left, top-right, and bottom-right.
```

---

## Prompt 4 — Empty state with suggestions

```
Design the first-run empty state of the same medical AI chat screen.

Centred vertically: a 72px soft teal circle at 12% opacity containing a teal medical
assistant icon. Below it a 22px semibold heading "How can I help today?" and a 16px grey
subtitle "Ask about your blood sugar, diet, medicines or symptoms. Available 24/7."

Below that, four stacked full-width suggestion chips — rounded 16px, white with a thin grey
border, left-aligned 16px text, a small teal icon on the left of each and a faint chevron on
the right:
- "My sugar is 250 — what should I do?"
- "What can I eat for breakfast?"
- "Why do my feet feel numb?"
- "Explain my last eye report"

The composer pill sits at the bottom as normal.

Keep it calm and uncluttered — lots of whitespace, nothing competing for attention.
```

---

## Prompt 5 — Hold-to-talk recording bar

```
Design a WhatsApp-style press-and-hold voice recording state for the bottom of the same
medical chat app.

The composer pill is replaced by a recording bar of the same height and radius:
- A pulsing red dot on the far left
- An elapsed timer "0:07" in a monospaced style
- A live audio waveform of thin rounded vertical teal bars of varying heights filling the
  middle, taller in the centre where the person is speaking louder
- Centred over the waveform, grey text with a left chevron: "◀ slide to cancel"
- On the right, the circular teal microphone button, enlarged and glowing, as though a
  finger is pressing it

Above the microphone button, floating, show a small rounded pill with an upward chevron and
a padlock icon — the slide-up-to-lock affordance.

Produce a second version showing the cancel state: the waveform replaced by a red trash
icon and the text "Release to cancel" in red.
```

---

## Prompt 6 — Animation frame sheet

```
Create a design specification sheet showing the animation states for a medical AI chat app,
laid out as labelled frames on a neutral background.

Row 1 — "Voice orb": six frames of a circular gradient orb, 96px, teal #0F766E to mint
#5EEAD4, showing the gradient rotated progressively further around the circle in each frame,
and the orb growing slightly larger in the middle frames as if reacting to a loud voice.

Row 2 — "Generating border": four frames of a rounded rectangle message bubble with a bright
mint arc of light travelling around its border — top-left, top-right, bottom-right,
bottom-left.

Row 3 — "Mic to send": four frames showing a circular teal button cross-fading from a
microphone icon to a paper-plane send icon, with the icon shrinking slightly as it fades out
and growing as the new one fades in.

Row 4 — "Amplitude bars": four frames of four vertical rounded teal bars at different
heights, showing them responding to quiet, medium, loud and quiet-again audio.

Label each row clearly. Clean, technical, documentation-style layout.
```

---

## Getting better results from Stitch

**Name colours by hex, always.** "Teal" gets you a random teal. `#0F766E` gets you the brand.

**Describe hierarchy, not just contents.** The sentence *"this card must be the loudest, highest
contrast element on the entire screen"* does more work than any adjective — it tells Stitch what
to sacrifice when the layout gets crowded.

**Ask for realistic content.** Real questions about blood sugar produce believable spacing; lorem
ipsum produces layouts that break the moment real Bengali text arrives.

**Iterate with "Edit this screen"** rather than re-prompting from scratch, so the visual language
stays consistent across all six screens.

**Then check the output against reality:**
- Bengali and Hindi run **20–30% longer** than English. Any element Stitch fits snugly will
  overflow. Re-run Prompt 1 with *"all interface text in Bengali"* to find what breaks.
- Verify the emergency card still dominates. Stitch tends to harmonise palettes, which is exactly
  the wrong instinct for a warning that must interrupt.
- Confirm body text is 16px+ and tap targets 48px+ before handing anything to implementation.

**What Stitch will not give you:** motion timing, state logic, or the safety rules in
[AI_ASSISTANT_UI_SPEC.md](AI_ASSISTANT_UI_SPEC.md) §1 and §4.1. Use its output as visual direction,
then build against the spec.

# Stitch Prompts — ClinQ Profile Screen & Theme Switching

Prompts for [Google Stitch](https://stitch.withgoogle.com) to design the redesigned
Profile screen and its light/dark theme control.

**How to use:** run **Prompt 1** first to establish the screen, then use *"Edit this
screen"* for 2–5 so they inherit the visual language. Companion spec:
[PROFILE_THEME_SPEC.md](PROFILE_THEME_SPEC.md).

Stitch renders static screens. Prompt 3 gets you both themes side by side so you can
compare them; the switching behaviour and timings live in the spec (§2, §5).

---

## Prompt 1 — Profile screen, light mode (run this first)

```
Design a mobile Profile settings screen for a diabetes care app used by patients
of an Indian physician. Users are mostly adults over 45, so text is large and
rows are generously tall.

Style: calm, clinical, trustworthy. Deep teal #0F766E as the primary colour,
near-white #F8FAFC page background, white cards, soft grey borders. No drop
shadows — use thin 1px borders instead. Rounded 16px cards. Clean sans-serif,
16px row text, generous spacing.

Layout top to bottom:

- App bar with the title "Profile", no back arrow.

- Centred header: an 88px circular avatar in pale teal containing a large teal
  letter "R"; below it the name "Rahul Das" in 22px semibold; below that
  "+91 98300 00011" in 15px grey; below that a small rounded pill chip reading
  "Type 2 · Patient".

- A section labelled "APPEARANCE" in small uppercase grey letter-spaced text,
  above a white card containing a full-width three-segment control, 48px tall.
  The three segments read "Light", "Dark" and "System", each with a small icon
  above or beside the label — a sun, a crescent moon, and a half-filled circle.
  The "System" segment is selected, filled solid teal with white text; the other
  two are transparent with grey text. Below the control, a small grey line of
  helper text: "Follows your phone's setting".

- A section labelled "LANGUAGE" above a white card containing three rounded
  choice chips side by side: "English", "বাংলা", "हिन्दी". "English" is
  selected in teal.

- A section labelled "ACCOUNT" above a white card with three rows, each 64px
  tall with a teal outline icon on the left, black 16px label, and a grey
  chevron on the right:
  - person icon, "Edit profile"
  - stethoscope icon, "Diabetes type", with grey text "Type 2" before the chevron
  - bell icon, "Notifications"

- A section labelled "CLINIC" above a white card with two rows:
  - phone icon, "Call the clinic"
  - info icon, "About ClinQ", with grey text "v1.0.0" before the chevron

- A full-width outlined button at the bottom with a logout icon and the text
  "Log out", in red #DC2626 with a red border and a white fill.

Plenty of whitespace between sections. Nothing should feel cramped.
```

---

## Prompt 2 — The same screen in dark mode

```
Now show the exact same Profile screen in dark mode, keeping every element in
the same position.

Dark palette:
- Page background: deep blue-grey #0F1720 — a soft dark, not pure black
- Cards: a slightly lighter blue-grey than the page, with thin subtle borders
- Primary teal becomes brighter: #14B8A6 instead of #0F766E
- Body text near-white, secondary text mid-grey
- The logout button's red stays clearly readable against the dark background

The "Dark" segment of the appearance control is now the selected one, filled
solid teal with white text.

Important: this must not be a simple colour inversion. Text must stay
comfortably readable for older eyes — avoid pure white on pure black, which
causes text to bloom and smear.
```

---

## Prompt 3 — Theme selector, all states

```
Create a component sheet for a three-segment theme selector control, shown on a
neutral background as design documentation.

The control is a full-width rounded rectangle, 48px tall, 12px radius, with a
thin border and three equal segments labelled "Light", "Dark" and "System",
each with a small icon: a sun, a crescent moon, and a half-filled circle.

Show six versions in two rows of three:

Row 1 — on a light background (#F8FAFC card, teal #0F766E selection):
1. "Light" selected
2. "Dark" selected
3. "System" selected

Row 2 — on a dark background (#0F1720 card, brighter teal #14B8A6 selection):
4. "Light" selected
5. "Dark" selected
6. "System" selected

In every version the selected segment is a solid teal fill with white text and
icon; the unselected segments are transparent with grey text and icon.

Label each version clearly. Clean, technical, documentation-style layout.
```

---

## Prompt 4 — Edit profile screen

```
Design an "Edit profile" form screen for the same medical app, matching the
Profile screen's style.

App bar: back arrow, title "Edit profile", and a teal "Save" text button on the
right.

Below it, a centred 88px teal-tinted circular avatar with the letter "R", and a
small teal text button beneath reading "Change photo".

Then a single white card, 16px radius, containing stacked form fields separated
by thin divider lines. Each field shows a small grey label above the value:
- "Full name" — Rahul Das
- "Phone number" — +91 98300 00011, greyed out and non-editable, with a small
  lock icon on the right
- "Email" — rahul.das@example.com
- "Date of birth" — 02 April 1975, with a calendar icon on the right
- "Gender" — Male, with a dropdown chevron

Below the card, small grey helper text: "Your phone number is your login and
cannot be changed here. Contact the clinic if it needs updating."

Produce both a light and a dark version.
```

---

## Prompt 5 — Diabetes type picker

```
Design a bottom sheet for choosing diabetes type, matching the same medical app
style.

The sheet covers the lower half of the screen with a 28px top radius and a small
grey drag handle at the top.

Title in 20px semibold: "Your diabetes type". Below it, 15px grey text: "This
helps the assistant give you the right guidance. Ask your doctor if you are not
sure."

Below that, five full-width selectable rows in a card, each 64px tall with a
radio circle on the right:
- "Type 1"
- "Type 2" (selected — teal filled radio, pale teal row background)
- "Gestational"
- "Prediabetes"
- "None / not diabetic"

Each row has a short grey sub-label under its title in 13px, for example under
Type 1: "The body makes no insulin", under Type 2: "The body does not use
insulin well".

At the bottom, a full-width teal "Save" button, 56px tall with a 28px radius,
and a plain grey "Cancel" text button beneath it.

Produce both a light and a dark version.
```

---

## Getting better results from Stitch

**Give the hex codes, always.** "Dark blue-grey" gets you a random dark. `#0F1720`
gets you the palette that is already in the app's `app_colors.dart`.

**Say what the dark theme must NOT be.** Stitch's default instinct for "dark mode"
is to invert. The instruction *"this must not be a simple colour inversion"* plus
the note about text blooming is what stops it producing pure white on pure black —
which is actively harder to read for the older patients this app is built for.

**Ask for both themes every time.** A component that only exists in light will be
built in light and patched later.

**Then check the output against reality:**
- Bengali and Hindi run **20–30% longer** than English. Re-run Prompt 1 with *"all
  interface text in Bengali"* — "Notifications" becomes "বিজ্ঞপ্তিসমূহ" and will
  test whether your rows still fit.
- Confirm rows are ≥48px and body text ≥16px before handing anything to build.
- Stitch will harmonise the logout red into the palette. Push back — it should stay
  clearly distinct from every other action on the screen.

**What Stitch will not give you:** the persistence logic, the 200ms segment
animation, or the contrast verification in §7 of the spec — which matters most,
because the emergency card's dark-mode colours have never been checked against a
contrast target. Use Stitch's output as visual direction, then build against
[PROFILE_THEME_SPEC.md](PROFILE_THEME_SPEC.md).

# ClinQ — Profile Screen & Theme Switching Specification

Design spec for redesigning the Profile screen and adding an in-app light/dark
theme control.

Scope: `mobile/lib/features/profile/`, `mobile/lib/shared/providers/`,
`mobile/lib/app.dart`. Target: Flutter 3.41, Material 3.

---

## 1. What already exists (read this first)

**Dark mode is already fully built.** `core/theme/app_theme.dart` builds both
themes from a single `_build(Brightness)` function, and `app.dart` already
passes both to `MaterialApp.router`:

```dart
theme: AppTheme.light(),
darkTheme: AppTheme.dark(),
themeMode: ThemeMode.system,   // ← hardcoded, this is the whole gap
```

Every screen already renders correctly in dark mode. It follows your phone's
system setting today. What is missing is not the theming — it is:

1. An in-app control to override the system setting.
2. Persistence of that choice across restarts.
3. A Profile screen worth putting it in.

That makes this a small, well-bounded change, not a re-theme.

### The current Profile screen

A single unstructured `ListView`: avatar, name, phone, the word "Patient",
three language chips, an "About ClinQ" tile, and a logout button. No grouping,
no sections, and nothing between the language chips and logout.

Also note: `profileEditProfile` ("Edit profile") already exists in all three
`.arb` files and is **never used** — no edit action is wired anywhere.

---

## 2. Three states, not a toggle

Offer **System / Light / Dark**, not an on-off switch.

A binary toggle has to pick a starting position, and whichever it picks is
wrong for the person whose phone is set the other way. More importantly it
permanently discards "follow my phone", which is what most people actually
want — their phone already switches at sunset and the app should follow.

For this app's users specifically, the choice is not cosmetic:

- Many patients are 45+ and have some degree of presbyopia or cataract. Dark
  backgrounds cause **halation** — white text blooming and smearing — which
  makes dark mode genuinely harder to read for them, not easier.
- Others read the app in bed at night beside a sleeping partner, where a white
  screen is the problem.
- Diabetic retinopathy affects contrast sensitivity. Neither theme is
  universally better; the patient is the only one who knows.

So: default to **System**, and let them override permanently in either
direction.

---

## 3. Theme persistence

Mirror `LocaleController` exactly — same pattern, same storage, same shape. It
already solves this problem for language and there is no reason for a second
approach.

```dart
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(_readInitial(_prefs));

  final SharedPreferences _prefs;
  static const _key = 'akd_theme_mode';

  static ThemeMode _readInitial(SharedPreferences prefs) {
    switch (prefs.getString(_key)) {
      case 'light': return ThemeMode.light;
      case 'dark':  return ThemeMode.dark;
      default:      return ThemeMode.system;   // also the fallback for junk
    }
  }

  Future<void> setMode(ThemeMode mode) async { ... }
}
```

Then in `app.dart`, one line changes:

```dart
themeMode: ref.watch(themeControllerProvider),
```

`sharedPreferencesProvider` is already overridden in `main.dart`, so no new
plumbing is needed. The switch is instant — `MaterialApp` rebuilds on the
provider change, exactly as the locale switch already does.

**Not** stored on the server. Theme is a per-device preference: the same
patient may want dark on their phone and light on a tablet. Language *is*
synced to the server (`PATCH /auth/me`) because it drives the language the
assistant replies in. Theme has no server-side meaning.

---

## 4. Screen structure

```
┌─────────────────────────────────────┐
│  Profile                            │  App bar, no back arrow (tab root)
├─────────────────────────────────────┤
│         ╭───────╮                   │
│         │   R   │                   │  Avatar — initial, teal tint
│         ╰───────╯                   │
│        Rahul Das                    │  22sp semibold
│      +91 98300 00011                │  15sp muted
│    ╭──────────────────╮             │
│    │  Type 2 · Patient │            │  Status chip
│    ╰──────────────────╯             │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ APPEARANCE                    │  │  Section label, 13sp, letter-spaced
│  │ ┌───────┬───────┬───────┐     │  │
│  │ │  ☀    │  ☾    │  ⚙    │     │  │  Segmented: Light / Dark / System
│  │ │ Light │ Dark  │System │     │  │  48dp tall, selected = teal fill
│  │ └───────┴───────┴───────┘     │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ LANGUAGE                      │  │
│  │  English    বাংলা    हिन्दी    │  │  Choice chips, each in own script
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ ACCOUNT                       │  │
│  │ 👤 Edit profile            ›  │  │
│  │ 🩺 Diabetes type      Type 2 ›  │  │  ← see §6
│  │ 🔔 Notifications           ›  │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │ CLINIC                        │  │
│  │ 📞 Call the clinic         ›  │  │  tel: launcher
│  │ ℹ  About ClinQ      v1.0.0  ›  │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │        ⎋  Log out             │  │  Danger outline, full width
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

Grouped cards rather than a flat list: it separates "how the app looks" from
"my account" from "the clinic", and it gives the screen somewhere to grow.

---

## 5. Component specs

### Theme selector

A three-segment control, full width, 48dp tall, 12dp radius.

| State | Fill | Text | Icon |
|---|---|---|---|
| Selected | `primary` `#0F766E` | white, w600 | white |
| Unselected | transparent | `onSurfaceVariant` | `onSurfaceVariant` |
| Container | `surfaceContainerHighest`, 1dp `outlineVariant` border | | |

Icons: `wb_sunny_outlined` / `dark_mode_outlined` / `brightness_auto_outlined`.

Selection slides between segments over **200ms `easeOutCubic`**. The theme
itself changes instantly — do not animate the whole screen's colours, which
looks like a rendering fault rather than a setting.

Each segment is its own semantic button announcing its selected state.

### Section cards

`surface` fill, 16dp radius, 1dp `outlineVariant` border, no shadow. Section
label above the card in 13sp, uppercase, `letterSpacing: 0.8`,
`onSurfaceVariant`.

### Rows

64dp minimum height, leading icon 22dp in `primary`, title 16sp, optional
trailing value in `onSurfaceVariant`, trailing chevron. Full-width tap target.

### Avatar

88dp circle, `primary` at 14% alpha, first initial at 34sp w800 in `primary`.
Falls back to `?` when the name is empty — never crash on missing data.

---

## 6. Put the diabetes type here

This closes a real gap. Diabetes type was removed from the register screen on
request, and the server applies `.default('type2')` to any registration that
omits it ([`auth.js:38`](backend/src/routes/auth.js#L38)). **Every patient who
signs up is therefore recorded as Type 2, whether or not that is true.**

Profile is the right place to collect it: the patient is calm, not mid-signup,
and can be told plainly why it is being asked.

Two things this needs that do not exist yet:

- `GET /auth/me` already returns `profile: PatientProfile`, which carries
  `diabetesType`. Reading it is free.
- `PATCH /auth/me` accepts `name, email, language, dateOfBirth, gender` — it
  does **not** accept `diabetesType`, because that field lives on
  `PatientProfile`, not `User`. Writing it needs a small backend addition.

Until that endpoint exists, show the value read-only with the note "Ask the
clinic to update this". Showing a wrong value the patient cannot correct is
worse than showing nothing.

---

## 7. Both themes must be verified, not assumed

The safety-critical surfaces already have dark variants in `app_colors.dart`
(`dangerBgDark #3F1414`, `warningBgDark #3A2A0A`). They must be checked, not
trusted:

- **Emergency card must hold 7:1 contrast in dark mode.** `danger #DC2626` on
  `dangerBgDark #3F1414` is a much narrower gap than `#DC2626` on `#FEE2E2`.
  If it fails, lighten the dark text tone rather than dimming the card.
- Urgent card, glucose flag colours, and the health-score ring all encode
  clinical meaning in colour. Check each in both themes.
- The chat composer pill, the generating bubble's border sweep, and the voice
  orb were all designed against the light palette. Check them dark.

Add a widget test that pumps the emergency card in both brightnesses and
asserts it renders — the existing `chat_ui_test.dart` already has the harness
for it.

---

## 8. Accessibility

- Every row ≥ 48dp; theme segments 48dp.
- Text scales to 200% without clipping. Test in **Bengali**, where strings run
  longest — "Appearance" is "চেহারা", but "Notifications" is
  "বিজ্ঞপ্তিসমূহ".
- Theme segments announce selected state to a screen reader.
- Colour is never the only signal: each theme segment carries an icon and a
  label, not just a fill.
- Logout confirms before acting (already implemented — keep it).

---

## 9. Implementation checklist

```
lib/shared/providers/theme_provider.dart      new — mirrors locale_provider.dart
lib/app.dart                                  themeMode: ref.watch(...)
lib/features/profile/presentation/
  profile_screen.dart                         rebuild with sections
  widgets/theme_selector.dart                 new — segmented control
  widgets/profile_section.dart                new — labelled card
  widgets/profile_row.dart                    new — icon/title/value/chevron
lib/l10n/app_{en,bn,hi}.arb                   new strings (below)
```

New strings needed in all three languages:

```
profileAppearance      "Appearance"
profileThemeLight      "Light"
profileThemeDark       "Dark"
profileThemeSystem     "System"
profileThemeSystemHint "Follows your phone's setting"
profileAccount         "Account"
profileClinic          "Clinic"
profileDiabetesType    "Diabetes type"
profileNotifications   "Notifications"
profileCallClinic      "Call the clinic"
profileVersion         "Version"
```

`profileEditProfile` already exists and is unused — wire it or drop it.

### Acceptance criteria

- [ ] Light / Dark / System all selectable, System is the default
- [ ] Choice survives an app restart
- [ ] Switching is instant, with no flash of the wrong theme on launch
- [ ] Emergency and urgent cards verified at 7:1 and 4.5:1 in **both** themes
- [ ] Every screen checked in dark mode, not just Profile
- [ ] All new strings localized in en / bn / hi
- [ ] 200% text scale in Bengali, no clipping
- [ ] Theme is device-local — not sent to the server
- [ ] `flutter analyze` clean, existing tests still pass

---

## 10. Out of scope

- **Server-side theme sync.** Deliberate; see §3.
- **Custom accent colours.** The teal is the brand and clinical colours carry
  meaning — letting patients recolour the app would let them recolour the
  emergency card.
- **True-black OLED mode.** Possible later; `surfaceDark #0F1720` is currently
  a soft dark that reduces halation for older eyes, which is the right default
  for this cohort.

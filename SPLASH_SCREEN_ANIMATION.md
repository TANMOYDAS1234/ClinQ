# ClinQ — Splash Screen Animation Brief

A brief for turning the current static splash (logo + spinner on emerald) into a
**premium, meaningful, smooth** intro animation.

**Golden rule:** the splash must never *add* waiting. It plays **over** app
bootstrap (auth restore + first route decision), targets **~2.0s**, and hands off
the instant the app is ready — whichever comes last, but never longer than ~2.4s.

---

## 1. Concept — "The First Beat"

The emblem doesn't just fade in. It **comes alive**: the mark draws itself, takes
**one heartbeat**, and that pulse **ripples outward** — the moment the clinic
"wakes up" for the patient. Calm emerald, one clean pulse, a shimmer on the
wordmark, then a seamless morph into the app.

It should feel like a **vital sign**, not a logo reveal. Restraint is the luxury:
one idea (a heartbeat), executed perfectly.

### Every element earns its motion (this is the "meaningful" part)

| Element | Motion | Why it means something |
|---|---|---|
| Heartbeat / ECG line | traces left → right, then a spike | Vitals, life — the daily glucose rhythm this app is about |
| The "C" arc | strokes on around the mark | The clinic *embracing* the patient |
| Mind / tree-branch | grows / branches out | The AI intelligence + health, growth |
| Medical cross | blooms with a soft spring overshoot | Care, medicine |
| Pulse ring | **one** ripple expands and fades | The heartbeat of the clinic reaching *you* |
| Wordmark shimmer | a single light sweep across "ClinQ" | Polish — the "premium" cue |

---

## 2. Palette (use these exactly — from `AppColors`)

| Role | Hex | Token |
|---|---|---|
| Ground (base) | `#064E3B` | `primary` |
| Ground mesh (subtle) | `#0B3B2E` → `#0F766E` | darker/teal shift |
| Emerald glow / accent | `#10B981` | `accent` |
| Mint (soft highlights, tagline) | `#D1FAE5` | `accentSoft` |
| Wordmark / ripple / shimmer | `#FFFFFF` (low alpha for FX) | — |
| AI-spectrum sweep (used *sparingly*, only in the ripple/shimmer) | `#0F766E` → `#06B6D4` → `#4F46E5` → `#7C3AED` | teal→cyan→indigo→violet |

Discipline: the **base is emerald**, the **hero is white/mint**. The rainbow
spectrum appears **only** as a whisper inside the pulse ring or the wordmark
shimmer — never as flat fills. That restraint is what reads as premium vs. gaudy.

---

## 3. Timeline (~2200ms — choreographed, never all-at-once)

| Time (ms) | What happens | Easing |
|---|---|---|
| 0–300 | Emerald ground; a soft **radial glow** blooms from center; faint medical-doodle texture fades in at ~6% and begins a slow drift | `easeOut` |
| 200–1000 | **Emblem draws in**: C-arc strokes on, tree/mind branches grow, ECG line traces across, cross scales in with a **spring overshoot**; emblem settles with a subtle lift + soft shadow | emphasized / spring |
| 800–1200 | **One heartbeat**: emblem scales `1.00 → 1.04 → 1.00`; a concentric **pulse ring** expands from it and fades | `easeInOut` |
| 1000–1600 | **Wordmark** "ClinQ" fades + rises ~12px; a **light sweep** shimmers across the letters; tagline "AI care for diabetes & hormones" fades in below | emphasized decelerate |
| 1600–2200 | Brief hold, then **exit**: whole scene scales up ~4% and cross-fades to the app — ideally a **shared-element** morph of the emblem to the login/header position | emphasized |

Stagger everything. Simultaneous = cheap; choreographed = expensive-feeling.

---

## 4. Motion specs

- **Easing:** use Material 3 emphasized curves. `Curves.easeOutCubic` for
  entrances, `Curves.easeInOutCubicEmphasized` for the exit, a spring
  (`SpringDescription`, damping ~0.6) for the cross/emblem settle.
- **Overshoot, not bounce:** ~4–6% overshoot max. More reads as toy-like.
- **60fps only:** animate **`transform` + `opacity`** (GPU-composited). No layout,
  no color-tween of large fills, no per-frame `MaskFilter.blur` on big areas.
- **Duration:** short. A splash that lingers past ~2.4s feels slow, not premium.

---

## 5. Implementation in Flutter — pick one

### Option A — **Rive** (recommended for the "crazy/premium" hero)
Best for the self-drawing emblem + ECG trace + ripple as one hand-crafted piece.
- Design the emblem animation once in the Rive editor, export `assets/rive/splash.riv`.
- Play once, listen for completion, then route.
- Lightweight, buttery, art-directed. Needs the `rive` package + an hour in the editor.

```dart
RiveAnimation.asset(
  'assets/rive/splash.riv',
  fit: BoxFit.contain,
  onInit: (artboard) {
    final ctrl = SimpleAnimation('intro', autoplay: true);
    artboard.addController(ctrl);
    ctrl.isActiveChanged.addListener(() {
      if (!ctrl.isActive) _finishSplash(); // animation done → route on
    });
  },
)
```

### Option B — **flutter_animate** (code-only, no Rive artist)
Great for the wordmark + emblem entrance + shimmer without leaving Dart.

```dart
// Emblem: fade + scale-in with a spring settle
AppLogo(size: 132)
  .animate()
  .fadeIn(duration: 400.ms, curve: Curves.easeOut)
  .scaleXY(begin: .82, end: 1, duration: 700.ms, curve: Curves.easeOutBack)
  .then(delay: 100.ms)
  .shimmer(duration: 900.ms, color: AppColors.accent.withOpacity(.5)); // one sweep

// Wordmark: rise + fade, staggered after the emblem
Text('ClinQ', style: ...)
  .animate(delay: 900.ms)
  .fadeIn(duration: 500.ms)
  .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic)
  .shimmer(delay: 200.ms, duration: 800.ms, color: Colors.white54);
```

### Option C — **Custom** (full control of the ECG + ripple)
`AnimationController` + `CustomPainter` for the two signature bits:

```dart
// Heartbeat trace: reveal an ECG path left→right using PathMetric.
void paint(Canvas c, Size s) {
  final metric = ecgPath.computeMetrics().first;
  final shown = metric.extractPath(0, metric.length * progress); // progress 0→1
  c.drawPath(shown, Paint()
    ..style = PaintingStyle.stroke..strokeWidth = 3
    ..color = AppColors.accentSoft..strokeCap = StrokeCap.round);
}

// Pulse ring: one expanding, fading circle.
final r = lerpDouble(0, s.width * .7, ripple)!;      // ripple 0→1
c.drawCircle(center, r, Paint()
  ..style = PaintingStyle.stroke..strokeWidth = 2
  ..color = Colors.white.withOpacity((1 - ripple) * .5));
```

> Also fine: a **Lottie** JSON if a motion designer supplies one (`lottie` package).

---

## 6. The seamless handoff (this is 50% of "smooth")

Two joins must be invisible:

1. **Native splash → Flutter splash.** Configure `flutter_native_splash` to show
   the **same emblem on `#064E3B`** so the OS splash and your animated splash are
   pixel-identical at the seam — no white flash, no jump.
   ```yaml
   flutter_native_splash:
     color: "#064E3B"
     image: assets/brand/logo_emblem_white.png
     android_12: { color: "#064E3B", image: assets/brand/... }
   ```
2. **Flutter splash → first screen.** Don't cut. Use a **shared-element / fade**
   into login (emblem morphs to the login header position), or a 250ms cross-fade.

**Precache** the logo in `main()` before `runApp` so frame 1 is ready:
`await precacheImage(AssetImage('assets/brand/logo.png'), context)`.

---

## 7. Performance & correctness

- Wrap the animated subtree in a **`RepaintBoundary`**.
- The doodle-texture drift must be a cheap transform, not a re-tile per frame.
- Kick off app bootstrap (auth restore, route decision) **in parallel** with the
  animation; route on `max(animationDone, bootstrapDone)`.
- Never block the first frame on network.

## 8. Accessibility

- Respect the OS **reduce-motion** setting
  (`MediaQuery.disableAnimationsOf(context)`): fall back to a **simple 300ms
  cross-fade** of the static emblem + wordmark — no trace, no ripple, no shimmer.
- Keep contrast high (white/mint on emerald passes AA).

## 9. Do / Don't

**Do:** one idea (the heartbeat) · choreograph · overshoot subtly · match the
native splash exactly · exit with a morph · keep it ≤ ~2.2s.

**Don't:** spin a generic loader · flat rainbow fills · animate everything at once ·
blur large areas every frame · make the user wait *for the animation*.
</content>

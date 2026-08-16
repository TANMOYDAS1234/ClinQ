import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The MedPin mark, in a square box — login, splash, the app lock.
///
/// Draws the *emblem*, not the full lockup. The lockup is nearly three times as
/// wide as it is tall, so squeezing it into a square with `BoxFit.cover` would
/// crop away the wordmark and leave a magnified fragment of the figure. Screens
/// that want the name next to the mark either set it in type themselves (the
/// splash does) or use [AppWordmark].
///
/// Wraps the asset so screens never hardcode the path, and so a change of
/// artwork is a one-file edit.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64, this.showShadow = false});

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // A soft brand-coloured lift under the mark. No clip and no fill: the
        // artwork is transparent line-work, and boxing it in a rounded tile
        // would read as an app icon pasted onto the screen.
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.accentOn(context).withValues(alpha: 0.22),
                  blurRadius: size * 0.28,
                  offset: Offset(0, size * 0.10),
                ),
              ]
            : null,
      ),
      child: Image.asset(
        'assets/brand/medpin_emblem.png',
        width: size,
        height: size,
        // contain, not cover — the emblem is slightly taller than it is wide,
        // and cover would shave its sides.
        fit: BoxFit.contain,
        // The logo is decorative wherever it appears — the screen title
        // already names the app, so announcing it again is noise.
        excludeFromSemantics: true,
      ),
    );
  }
}

/// The full horizontal lockup: mark + "MedPin" + the tagline.
///
/// Sized by height, with the width left to follow the artwork's own ratio —
/// constraining both is what distorts a lockup.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.height = 34});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/brand/medpin_logo.png',
      height: height,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}

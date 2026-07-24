import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// The ClinQ brand mark.
///
/// Wraps the raster asset so screens never hardcode the path, and so a future
/// change of artwork is a one-file edit. The rounded corners are baked into
/// the PNG; the clip here only guards against the asset being swapped for a
/// square one later.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64, this.showShadow = false});

  final double size;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.22;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: size * 0.25,
                  offset: Offset(0, size * 0.08),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/brand/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          // The logo is decorative wherever it appears — the screen title
          // already names the app, so announcing it again is noise.
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

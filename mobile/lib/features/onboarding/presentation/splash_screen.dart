import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/app_logo.dart';

/// Shown briefly while the router's redirect logic figures out where to send
/// the user (language picker / login / home) based on stored preferences and
/// auth state. Also the initial route target while [AuthController] bootstraps
/// from secure storage.
///
/// It used to be a flat navy field with the mark on a white plate — the plate
/// existed only because navy line-work on a navy ground is invisible. Turning
/// the ground light removes the problem the plate was solving, so the mark can
/// sit on the screen directly.
///
/// It is on screen for well under a second, so it does one thing: say which
/// app opened, calmly, in the same light the rest of the app uses.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.surface,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [T.primaryTint, T.surface],
            stops: [0, 0.55],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(size: 96),
              const SizedBox(height: T.s5),
              Text('MedPin', style: T.display.copyWith(color: T.primary)),
              const SizedBox(height: T.s1),
              Text(
                'Care connected',
                style: T.small.copyWith(
                  color: T.inkMuted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: T.s8),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(T.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

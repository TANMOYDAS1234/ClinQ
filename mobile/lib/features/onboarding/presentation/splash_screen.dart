import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/app_logo.dart';

/// Shown briefly while the router's redirect logic figures out where to
/// send the user (language picker / login / home) based on stored
/// preferences and auth state. Also the actual initial route target while
/// [AuthController] bootstraps from secure storage.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // On its own white plate. The mark is deep-blue line-work and the
            // splash ground is the same deep blue, so reversing it out would
            // leave a navy figure on a navy screen — invisible for the second
            // the splash is up.
            Container(
              width: 148,
              height: 148,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(34),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(child: AppLogo(size: 104)),
            ),
            const SizedBox(height: 24),
            const Text(
              'MedPin',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Care connected',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

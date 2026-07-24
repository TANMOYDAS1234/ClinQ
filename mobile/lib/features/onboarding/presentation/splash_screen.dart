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
            // The emblem is a teal mark on a light ground, so it is shown on
            // its white plate rather than reversed out against the teal
            // background.
            const AppLogo(size: 132),
            const SizedBox(height: 24),
            const Text(
              'ClinQ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
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

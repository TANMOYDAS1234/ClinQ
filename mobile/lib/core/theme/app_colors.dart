import 'package:flutter/material.dart';

/// Brand and clinical-status colours. Kept as a single source of truth so
/// glucose flags, alert severities, etc. always render consistently.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0F766E); // teal
  static const Color primaryDark = Color(0xFF14B8A6);
  static const Color surfaceLight = Color(0xFFF8FAFC);
  static const Color surfaceDark = Color(0xFF0F1720);

  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);
  static const Color success = Color(0xFF059669);

  static const Color dangerBg = Color(0xFFFEE2E2);
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color successBg = Color(0xFFD1FAE5);

  static const Color dangerBgDark = Color(0xFF3F1414);
  static const Color warningBgDark = Color(0xFF3A2A0A);
  static const Color successBgDark = Color(0xFF0C2E22);

  /// Glucose reading flag → colour, per contract flags:
  /// severe_low, low, in_range, very_high, critical_high.
  static Color forGlucoseFlag(String flag) {
    switch (flag) {
      case 'severe_low':
      case 'critical_high':
        return danger;
      case 'low':
      case 'very_high':
        return warning;
      case 'in_range':
        return success;
      default:
        return success;
    }
  }

  /// Triage / alert urgency ladder: routine < advice < urgent < emergency.
  static Color forUrgency(String urgency) {
    switch (urgency) {
      case 'emergency':
        return danger;
      case 'urgent':
        return warning;
      case 'advice':
        return primary;
      case 'routine':
      default:
        return success;
    }
  }
}

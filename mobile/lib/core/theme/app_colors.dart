import 'package:flutter/material.dart';

/// Brand and clinical-status colours. Kept as a single source of truth so
/// glucose flags, alert severities, etc. always render consistently.
class AppColors {
  AppColors._();

  // "Clinical Precision" palette. Deep forest green rather than the previous
  // teal: it reads as clinical and settled rather than techy, and holds enough
  // contrast to carry white text on primary buttons without a second tone.
  static const Color primary = Color(0xFF064E3B);

  /// Lighter counterpart used on dark surfaces, where the deep green would sink
  /// into the background.
  static const Color primaryDark = Color(0xFF10B981);

  /// Mint fill behind selected tabs, badges and quiet emphasis.
  static const Color accentSoft = Color(0xFFD1FAE5);

  /// The brighter green, for accents that must read at small sizes.
  static const Color accent = Color(0xFF10B981);

  /// Near-white, with only a trace of cool to stop it glaring. Deliberately not
  /// tinted toward the brand green — a clinical screen read all day should be
  /// neutral paper, not a coloured wash.
  static const Color surfaceLight = Color(0xFFFBFCFD);
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

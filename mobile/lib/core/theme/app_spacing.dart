/// Consistent spacing scale used across the app.
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Minimum recommended tap target, per the design brief (44px+), rounded
  /// up slightly for older patients tapping with less precision.
  static const double minTapTarget = 48;

  /// The radius language, matching the reference kit: cards sit *inside*
  /// controls, not the other way round. These were inverted — a 16px card
  /// holding a 12px button reads as two unrelated shapes.
  static const double cardRadius = 12;
  static const double buttonRadius = 16;

  /// Sheets, dialogs and the one leading card on a screen.
  static const double sheetRadius = 20;
}

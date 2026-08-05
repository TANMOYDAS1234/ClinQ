import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Material 3 theme for ClinQ.
///
/// Deliberately does NOT set a custom `fontFamily`: the platform default
/// (Roboto/Noto on Android, San Francisco on iOS) already ships full
/// Bengali and Devanagari glyph coverage, whereas most bundled display
/// fonts do not. Overriding it risks tofu boxes for bn/hi users.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    var colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      error: AppColors.danger,
    );

    // Material 3 derives every surface from the seed, so a deep green primary
    // washes the whole light theme faintly green. Fine for a brand app, wrong
    // for a clinical one — the surfaces are pulled back to near-neutral so the
    // green reads as deliberate accent rather than as a tint over everything.
    if (!isDark) {
      colorScheme = colorScheme.copyWith(
        surface: const Color(0xFFFBFCFD),
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFF7F9FB),
        surfaceContainer: const Color(0xFFF2F5F8),
        surfaceContainerHigh: const Color(0xFFEDF1F5),
        surfaceContainerHighest: const Color(0xFFE8EDF2),
        outlineVariant: const Color(0xFFDDE3EA),
      );
    }

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
    );

    // Minimum body text 16sp, headings 20-28sp, high contrast.
    final textTheme = base.textTheme
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.35),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        // Material 3 tints the bar as content scrolls under it. With a green
        // seed that shows as a creeping green wash on an otherwise white
        // header, so the bar is held flat.
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          // Flat. A raised primary button under a Material 3 tint picks up a
          // grey wash on press that reads as a rendering fault.
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          side: BorderSide(color: colorScheme.outlineVariant, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // Selection was unthemed, so the handles took the raw seed colour and the
      // highlight was nearly the same shade as the text behind it — hard to see
      // what was selected, and harder to aim at a handle sitting on the field's
      // border. Brand-coloured handles over a light wash keep both readable.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? colorScheme.surfaceContainerHigh : Colors.white,
        // Roomier fields — the old height read as cramped/narrow on the auth
        // screens. Taller with a touch more side padding.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 19,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        labelStyle: textTheme.bodyMedium,
        hintStyle: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        // Flat mint pill rather than the tonal primaryContainer, which under a
        // deep-green seed comes out muddy against white.
        indicatorColor: isDark ? AppColors.primaryDark.withValues(alpha: 0.22) : AppColors.accentSoft,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.bodySmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? (isDark ? AppColors.primaryDark : AppColors.primary)
                : colorScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? (isDark ? AppColors.primaryDark : AppColors.primary)
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      // Sheets rise with a proper radius rather than square corners — the
      // attach picker and every confirm dialog inherit this.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      // Hairline rather than a visible rule: on a light clinical surface a
      // heavy divider reads as a seam between unrelated things.
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.8),
        space: 1,
        thickness: 1,
      ),
    );
  }
}

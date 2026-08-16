import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// The shared surfaces of the clinician panel.
///
/// Every screen was drawing its own card: some with a border and no shadow,
/// some with a shadow and no border, radii between 12 and 20, and section
/// headings set at four different sizes. Individually each looked fine; put on
/// consecutive screens they read as several products stitched together, which
/// is the opposite of what a doctor should feel when they hand the phone to
/// someone else.
///
/// One card, one heading, one accent panel — so the whole panel looks drawn by
/// the same hand.

/// The panel's card. A hairline plus a very soft lift, never both loud.
///
/// The shadow is nearly invisible on its own; what it does is separate a white
/// card from a near-white page without needing a heavy border to do it. A
/// border alone reads as a wireframe, a strong shadow reads as a pop-up.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.accentEdge,
    this.background,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// A colour rail down the leading edge, for rows that carry a severity.
  final Color? accentEdge;
  final Color? background;

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final content = Padding(padding: padding, child: child);

    return Container(
      decoration: BoxDecoration(
        color: background ?? scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0B1B33).withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: accentEdge == null
              ? content
              : IntrinsicHeight(
                  child: Row(
                    children: [
                      Container(width: 4, color: accentEdge),
                      Expanded(child: content),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// A section heading, with an optional trailing action.
///
/// One size and weight everywhere, so scanning down a screen the headings form
/// a single column of the same thing rather than a staircase.
class PanelSectionHeader extends StatelessWidget {
  const PanelSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: scheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.accentOn(context),
              ),
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

/// The brand-filled panel: the daily summary, the prescribing block.
///
/// Deliberately rare. It is the loudest surface in the panel, so it is spent on
/// the one thing a screen is *for* — everything else stays white, and the eye
/// goes where the colour is.
class PanelFeatureCard extends StatelessWidget {
  const PanelFeatureCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        // A short gradient, not a flat fill: flat #003399 over a large area
        // goes muddy on an OLED panel, and the slight lift keeps it looking
        // printed rather than painted.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF00297A), Color(0xFF0A47B8)],
        ),
        borderRadius: BorderRadius.circular(PanelCard.radius),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// A small status pill — severity, state, a count.
class PanelPill extends StatelessWidget {
  const PanelPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: icon == null ? 10 : 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

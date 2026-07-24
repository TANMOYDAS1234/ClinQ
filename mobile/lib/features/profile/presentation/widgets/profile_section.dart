import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// A labelled group of settings rows.
///
/// Grouping separates "how the app looks" from "my account" from "the clinic",
/// which a flat list cannot do, and gives the screen somewhere to grow.
class ProfileSection extends StatelessWidget {
  const ProfileSection({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          // Clipped so a row's ripple stays inside the rounded corners.
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// One tappable settings row: icon, title, optional trailing value, chevron.
class ProfileRow extends StatelessWidget {
  const ProfileRow({
    super.key,
    required this.icon,
    required this.title,
    this.value,
    this.subtitle,
    this.onTap,
    this.trailingIcon = Icons.chevron_right_rounded,
    this.isDanger = false,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? value;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData trailingIcon;
  final bool isDanger;

  /// False on the last row of a section, so no line hangs under it.
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDanger
        ? AppColors.danger
        : (isDark ? AppColors.primaryDark : AppColors.primary);

    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 12,
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: accent),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          color: isDanger ? AppColors.danger : scheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 13, height: 1.35, color: accent),
                        ),
                      ],
                    ],
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    value!,
                    style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(trailingIcon, size: 22, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ],
    );
  }
}

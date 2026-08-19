import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/providers/theme_provider.dart';

/// Three-segment appearance control: Light · Dark · System.
///
/// Geometry from the design spec — 48dp tall, 12dp radius, 1dp border, 4dp
/// internal padding. The selection slides between segments; the theme itself
/// changes instantly, because animating the whole screen's colours reads as a
/// rendering fault rather than a setting.
class ThemeSelector extends ConsumerWidget {
  const ThemeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = ref.watch(themeControllerProvider);

    // Brighter teal on dark, per the palette — #0F766E does not carry enough
    // luminance against #0F1720.
    final activeColor = isDark ? AppColors.primaryDark : AppColors.primary;

    final segments = <({ThemeMode mode, IconData icon, String label})>[
      (mode: ThemeMode.light, icon: Icons.light_mode_outlined, label: l10n.profileThemeLight),
      (mode: ThemeMode.dark, icon: Icons.dark_mode_outlined, label: l10n.profileThemeDark),
      (mode: ThemeMode.system, icon: Icons.contrast_rounded, label: l10n.profileThemeSystem),
    ];

    return Container(
      height: 60,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // `surface`, not `surfaceContainerHighest` — the latter is a heavy
        // mid-grey in Material 3's light scheme, which read as a muddy box
        // sitting on the near-white page and clashed with the white section
        // cards below it. This matches those cards exactly.
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      // stretch, so each segment (and its selected pill) fills the full height
      // instead of shrink-wrapping the text into a thin band — the "narrow"
      // strip look. A 2px gap keeps the selected pill from touching its
      // neighbours.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == segments.length - 1 ? 0 : 3),
                child: _Segment(
                  icon: segments[i].icon,
                  label: segments[i].label,
                  selected: current == segments[i].mode,
                  activeColor: activeColor,
                  onTap: () => ref.read(themeControllerProvider.notifier).setMode(segments[i].mode),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? Colors.white : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: foreground),
              const SizedBox(width: 8),
              // Bengali "সিস্টেম" and Hindi "सिस्टम" are wider than "System",
              // so the label shrinks rather than overflowing the segment.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

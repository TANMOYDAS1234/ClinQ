import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// First-run state. The suggestion cards double as a demonstration: the first
/// one visibly produces real guidance, which teaches patients this is worth
/// opening when something is actually wrong.
class ChatEmptyState extends StatelessWidget {
  const ChatEmptyState({super.key, required this.onSuggestionTap});

  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final suggestions = [
      (icon: Icons.water_drop_outlined, text: l10n.chatSuggestionSugar),
      (icon: Icons.restaurant_outlined, text: l10n.chatSuggestionDiet),
      (icon: Icons.directions_walk_rounded, text: l10n.chatSuggestionFeet),
      (icon: Icons.visibility_outlined, text: l10n.chatSuggestionEye),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              // Flat mint rather than a tint of primary: a translucent green
              // over the dotted background picked up the dots and looked dirty.
              color: AppColors.accentSoftOn(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medical_services_outlined,
              color: AppColors.accentOn(context),
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.chatEmptyTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.chatEmptyBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final s in suggestions) ...[
          _SuggestionCard(
            icon: s.icon,
            text: s.text,
            onTap: () => onSuggestionTap(s.text),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.accentOn(context)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 16, height: 1.4)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right_rounded, size: 22, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

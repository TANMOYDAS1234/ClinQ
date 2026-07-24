import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Lets the patient state their diabetes type.
///
/// This matters more than an ordinary setting. Diabetes type is not collected
/// at registration, and the server applies `.default('type2')` to any
/// registration that omits it — so every patient is stored as Type 2 until
/// they say otherwise. Type governs DKA risk, insulin dependence and the
/// advice the assistant gives, so a Type 1 patient silently recorded as Type 2
/// is a real clinical problem, not a cosmetic one.
///
/// Returns the chosen code, or null if cancelled.
class DiabetesTypeSheet extends StatefulWidget {
  const DiabetesTypeSheet({super.key, this.initial});

  final String? initial;

  static Future<String?> show(BuildContext context, {String? initial}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      builder: (_) => DiabetesTypeSheet(initial: initial),
    );
  }

  @override
  State<DiabetesTypeSheet> createState() => _DiabetesTypeSheetState();
}

class _DiabetesTypeSheetState extends State<DiabetesTypeSheet> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    // Every value the server's enum accepts, each with a one-line explanation —
    // "Type 2" means nothing to a newly diagnosed patient.
    final options = <({String code, String label, String desc})>[
      (code: 'type1', label: l10n.authDiabetesType1, desc: l10n.profileDiabetesType1Desc),
      (code: 'type2', label: l10n.authDiabetesType2, desc: l10n.profileDiabetesType2Desc),
      (
        code: 'gestational',
        label: l10n.authDiabetesTypeGestational,
        desc: l10n.profileDiabetesGestationalDesc,
      ),
      (
        code: 'prediabetes',
        label: l10n.authDiabetesTypePrediabetes,
        desc: l10n.profileDiabetesPrediabetesDesc,
      ),
      (code: 'none', label: l10n.authDiabetesTypeNone, desc: l10n.profileDiabetesNoneDesc),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.profileDiabetesSheetTitle,
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.profileDiabetesSheetBody,
                style: TextStyle(fontSize: 15, height: 1.45, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      _Option(
                        label: options[i].label,
                        description: options[i].desc,
                        selected: _selected == options[i].code,
                        accent: accent,
                        onTap: () => setState(() => _selected = options[i].code),
                      ),
                      if (i != options.length - 1)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: scheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                height: AppSpacing.minTapTarget + 8,
                child: ElevatedButton(
                  // Disabled until a choice is made — saving "whatever was
                  // already there" is how the wrong default gets confirmed.
                  onPressed: _selected == null
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                  child: Text(
                    l10n.profileSave,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: Text(l10n.commonCancel, style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.description,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      label: '$label. $description',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
          color: selected ? accent.withValues(alpha: 0.10) : null,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                size: 24,
                color: selected ? accent : scheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

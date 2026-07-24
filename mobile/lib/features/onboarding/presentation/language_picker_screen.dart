import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/widgets/app_button.dart';

class _LanguageOption {
  const _LanguageOption(this.code, this.label, this.subLabel);
  final String code;
  final String label;
  final String subLabel;
}

const _options = [
  _LanguageOption('en', 'English', 'Continue in English'),
  _LanguageOption('bn', 'বাংলা', 'বাংলায় চালিয়ে যান'),
  _LanguageOption('hi', 'हिन्दी', 'हिन्दी में जारी रखें'),
];

/// First-run-only screen (see `LocaleController.hasChosenLanguage`). Shown
/// before login/register so the auth screens themselves can already be
/// localized.
class LanguagePickerScreen extends ConsumerStatefulWidget {
  const LanguagePickerScreen({super.key});

  @override
  ConsumerState<LanguagePickerScreen> createState() => _LanguagePickerScreenState();
}

class _LanguagePickerScreenState extends ConsumerState<LanguagePickerScreen> {
  String _selected = 'en';

  @override
  Widget build(BuildContext context) {
    // This screen runs *before* a language has been chosen, so the app locale
    // cannot drive its copy. Overriding the locale with the currently
    // highlighted option makes the heading, subtitle and button preview that
    // language as soon as it is tapped — the point of the screen is to show
    // the user what they are choosing.
    return Localizations.override(
      context: context,
      locale: Locale(_selected),
      child: Builder(builder: _buildBody),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Icon(Icons.translate_rounded, size: 40, color: AppColors.primary),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.languagePickerTitle,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.languagePickerSubtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.xl),
              Expanded(
                child: ListView.separated(
                  itemCount: _options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final option = _options[index];
                    final isSelected = option.code == _selected;
                    return _LanguageTile(
                      option: option,
                      isSelected: isSelected,
                      onTap: () => setState(() => _selected = option.code),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: l10n.continueButton,
                onPressed: () async {
                  await ref.read(localeControllerProvider.notifier).setLanguage(_selected);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.option, required this.isSelected, required this.onTap});

  final _LanguageOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected ? scheme.primaryContainer : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget + 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: isSelected ? AppColors.primary : scheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(option.subLabel, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: isSelected ? AppColors.primary : scheme.outlineVariant,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

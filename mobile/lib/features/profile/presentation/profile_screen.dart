import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'profile_providers.dart';
import 'widgets/diabetes_type_sheet.dart';
import 'widgets/profile_section.dart';
import 'widgets/theme_selector.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changeLanguage(WidgetRef ref, String code) async {
    await ref.read(localeControllerProvider.notifier).setLanguage(code);
    ref.read(authControllerProvider.notifier).updateLocalUserLanguage(code);
    // Best-effort sync: the UI has already switched, and the account copy
    // matters only for what the assistant replies in when the client omits it.
    try {
      await ref.read(authRepositoryProvider).updateMe(language: code);
    } on ApiException {
      // Non-fatal — the local preference still applies.
    }
  }

  Future<void> _pickDiabetesType(BuildContext context, WidgetRef ref, String? current) async {
    // Captured before the await — the sheet is an async gap, and reaching for
    // the context after it is what the lint is warning about.
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final chosen = await DiabetesTypeSheet.show(context, initial: current);
    if (chosen == null || chosen == current) return;

    try {
      await ref.read(authRepositoryProvider).updateDiabetesType(chosen);
      ref.invalidate(diabetesTypeProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    } on ApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.commonSomethingWentWrong)));
    }
  }

  Future<void> _callClinic() async {
    await launchUrl(Uri(scheme: 'tel', path: AppConfig.clinicPhoneNumber));
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.authLogoutConfirmTitle),
        content: Text(l10n.authLogoutConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.profileLogout, style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  String _diabetesLabel(AppLocalizations l10n, String? code) => switch (code) {
    'type1' => l10n.authDiabetesType1,
    'type2' => l10n.authDiabetesType2,
    'gestational' => l10n.authDiabetesTypeGestational,
    'prediabetes' => l10n.authDiabetesTypePrediabetes,
    'none' => l10n.authDiabetesTypeNone,
    _ => l10n.profileDiabetesTypeNotSet,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    final user = ref.watch(authControllerProvider).user;
    final currentLocale = ref.watch(localeControllerProvider);
    final diabetesType = ref.watch(diabetesTypeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.profileTitle,
          style: TextStyle(color: accent, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        children: [
          _Header(user: user, accent: accent),
          const SizedBox(height: AppSpacing.xl),

          // ---- Appearance -----------------------------------------------
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
            child: Text(
              l10n.profileAppearance.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const ThemeSelector(),
          const SizedBox(height: AppSpacing.lg),

          // ---- Language --------------------------------------------------
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
            child: Text(
              l10n.profileLanguage.toUpperCase(),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              // Each option always renders in its own script, so a Hindi
              // speaker can find "हिन्दी" while the app is still in English.
              _LangChip(
                label: l10n.languageEnglish,
                selected: currentLocale?.languageCode == 'en',
                accent: accent,
                onTap: () => _changeLanguage(ref, 'en'),
              ),
              _LangChip(
                label: l10n.languageBengali,
                selected: currentLocale?.languageCode == 'bn',
                accent: accent,
                onTap: () => _changeLanguage(ref, 'bn'),
              ),
              _LangChip(
                label: l10n.languageHindi,
                selected: currentLocale?.languageCode == 'hi',
                accent: accent,
                onTap: () => _changeLanguage(ref, 'hi'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---- Account ---------------------------------------------------
          ProfileSection(
            label: l10n.profileAccount,
            children: [
              ProfileRow(
                icon: Icons.person_outline_rounded,
                title: l10n.profileEditProfile,
                onTap: () => context.push('/profile/edit'),
              ),
              ProfileRow(
                icon: Icons.bloodtype_outlined,
                title: l10n.profileDiabetesType,
                value: _diabetesLabel(l10n, diabetesType),
                onTap: () => _pickDiabetesType(context, ref, diabetesType),
              ),
              ProfileRow(
                icon: Icons.notifications_none_rounded,
                title: l10n.profileNotifications,
                showDivider: false,
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(l10n.profileNotifications),
                    content: Text(l10n.profileNotificationsBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(l10n.commonOk),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ---- Clinic ----------------------------------------------------
          ProfileSection(
            label: l10n.profileClinic,
            children: [
              ProfileRow(
                icon: Icons.phone_outlined,
                title: l10n.profileCallClinic,
                trailingIcon: Icons.open_in_new_rounded,
                onTap: _callClinic,
              ),
              ProfileRow(
                icon: Icons.info_outline_rounded,
                title: l10n.profileAbout,
                value: 'v${AppConfig.appVersion}',
                showDivider: false,
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: AppConfig.appName,
                  applicationVersion: 'v${AppConfig.appVersion}',
                ),
              ),
            ],
          ),

          // ---- Logout ----------------------------------------------------
          SizedBox(
            width: double.infinity,
            height: AppSpacing.minTapTarget + 8,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                ),
              ),
              onPressed: () => _confirmLogout(context, ref),
              icon: const Icon(Icons.logout_rounded, size: 22),
              label: Text(
                l10n.profileLogout,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              l10n.profileFooter,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.user, required this.accent});

  final AppUser? user;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = user?.name ?? '';

    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: 0.35), width: 2),
          ),
          child: Center(
            child: Text(
              // Never crash on a missing name — an empty account still renders.
              (name.isNotEmpty ? name[0] : '?').toUpperCase(),
              style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800, color: accent),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(
          user?.phone ?? '',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            l10n.profilePatient,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          // No `alignment` here. A Container with an alignment and loose
          // constraints expands to the maximum width allowed — which made each
          // chip fill the row and stack vertically instead of sitting side by
          // side. The Center below does the same job without the growth.
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: selected ? accent : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? accent : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

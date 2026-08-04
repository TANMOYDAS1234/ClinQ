import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../shared/providers/app_lock_provider.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/widgets/fullscreen_photo.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../appointments/data/clinic_repository.dart';
import '../../auth/domain/user.dart';
import '../../auth/presentation/auth_controller.dart';
import 'widgets/profile_section.dart';
import 'widgets/theme_selector.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeLanguage(String code) async {
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

  /// Pick a photo, upload it as an `avatar` asset, then point the account at it.
  /// The returned user carries the new `avatarUrl`, so swapping it into auth
  /// state refreshes the avatar everywhere without a refetch.
  Future<void> _changeAvatar() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final source = await _pickImageSource();
    if (source == null) return;

    final XFile? file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final asset = await ref.read(uploadRepositoryProvider).uploadImage(
        path: file.path,
        filename: file.name,
        kind: UploadKind.avatar,
      );
      final user = await ref.read(authRepositoryProvider).updateMe(avatarAssetId: asset.id);
      ref.read(authControllerProvider.notifier).replaceUser(user);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
    } on ApiException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.chatAttachFailed)));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<ImageSource?> _pickImageSource() {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.chatAttachCamera),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.chatAttachGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickGlucoseUnit() async {
    final l10n = AppLocalizations.of(context);
    final current = ref.read(glucoseUnitProvider);
    final chosen = await showModalBottomSheet<GlucoseUnit>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.profileGlucoseUnit,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final unit in GlucoseUnit.values)
              ListTile(
                title: Text(unit.label, style: const TextStyle(fontSize: 16)),
                trailing: unit == current
                    ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, unit),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && chosen != current) {
      await ref.read(appPreferencesProvider.notifier).setGlucoseUnit(chosen);
    }
  }

  Future<void> _toggleAppLock(bool enable) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(appLockProvider.notifier);

    if (enable) {
      if (!await controller.canUse()) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.appLockUnavailable)));
        return;
      }
      final ok = await controller.enable(l10n.appLockPrompt);
      if (!ok) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.appLockUnavailable)));
      }
    } else {
      await controller.disable();
    }
  }

  Future<void> _callClinic() async {
    final phone = ref.read(clinicPhoneProvider).valueOrNull ?? AppConfig.clinicPhoneNumber;
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }

  Future<void> _confirmLogout() async {
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    final user = ref.watch(authControllerProvider).user;
    final currentLocale = ref.watch(localeControllerProvider);
    final glucoseUnit = ref.watch(glucoseUnitProvider);
    final lockEnabled = ref.watch(appLockProvider).enabled;

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
          _Header(
            user: user,
            accent: accent,
            uploading: _uploadingAvatar,
            onEditPhoto: _uploadingAvatar ? null : _changeAvatar,
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Appearance -----------------------------------------------
          _SectionLabel(l10n.profileAppearance),
          const ThemeSelector(),
          const SizedBox(height: AppSpacing.lg),

          // ---- Language --------------------------------------------------
          _SectionLabel(l10n.profileLanguage),
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
                onTap: () => _changeLanguage('en'),
              ),
              _LangChip(
                label: l10n.languageBengali,
                selected: currentLocale?.languageCode == 'bn',
                accent: accent,
                onTap: () => _changeLanguage('bn'),
              ),
              _LangChip(
                label: l10n.languageHindi,
                selected: currentLocale?.languageCode == 'hi',
                accent: accent,
                onTap: () => _changeLanguage('hi'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---- Preferences ----------------------------------------------
          ProfileSection(
            label: l10n.profilePreferences,
            children: [
              ProfileRow(
                icon: Icons.water_drop_outlined,
                title: l10n.profileGlucoseUnit,
                value: glucoseUnit.label,
                showDivider: false,
                onTap: _pickGlucoseUnit,
              ),
            ],
          ),

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
                icon: Icons.favorite_outline_rounded,
                title: l10n.profileHealthDetails,
                onTap: () => context.push('/profile/health'),
              ),
              ProfileRow(
                icon: Icons.notifications_none_rounded,
                title: l10n.profileNotifications,
                showDivider: false,
                onTap: () => context.push('/profile/notifications'),
              ),
            ],
          ),

          // ---- Security --------------------------------------------------
          _SectionLabel(l10n.profileSecurity),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: SwitchListTile.adaptive(
              value: lockEnabled,
              onChanged: _toggleAppLock,
              activeThumbColor: accent,
              secondary: Icon(Icons.lock_outline_rounded, color: accent),
              title: Text(l10n.profileAppLock, style: const TextStyle(fontSize: 16)),
              subtitle: Text(l10n.profileAppLockSub, style: const TextStyle(fontSize: 13)),
              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

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
              onPressed: _confirmLogout,
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

/// The small-caps section heading used for the inline (non-boxed) sections.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.user,
    required this.accent,
    required this.uploading,
    required this.onEditPhoto,
  });

  final AppUser? user;
  final Color accent;
  final bool uploading;
  final VoidCallback? onEditPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final name = user?.name ?? '';

    return Column(
      children: [
        Semantics(
          button: true,
          label: l10n.profileChangePhoto,
          child: GestureDetector(
            onTap: onEditPhoto,
            // Hold to view the photo full-screen (only when one is set).
            onLongPress: user?.avatarUrl != null
                ? () => FullscreenPhoto.show(context, user!.avatarUrl)
                : null,
            child: Stack(
              children: [
                UserAvatar(name: name, avatarUrl: user?.avatarUrl, accent: accent, size: 96),
                // Dim + spinner while the new photo is uploading.
                if (uploading)
                  Positioned.fill(
                    child: ClipOval(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45),
                        child: const Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                // Camera badge in the corner.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 2.5),
                    ),
                    child: const Icon(Icons.photo_camera_rounded, size: 15, color: Colors.white),
                  ),
                ),
              ],
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

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
import '../../../shared/widgets/fullscreen_photo.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../profile/presentation/widgets/profile_section.dart';
import '../../profile/presentation/widgets/theme_selector.dart';

/// Full profile for doctor and staff — the clinician counterpart of the patient
/// [ProfileScreen]: avatar, edit details, appearance, language, app lock, a
/// shortcut to clinical alerts, and sign-out.
class ClinicianMoreScreen extends ConsumerStatefulWidget {
  const ClinicianMoreScreen({super.key});

  @override
  ConsumerState<ClinicianMoreScreen> createState() => _ClinicianMoreScreenState();
}

class _ClinicianMoreScreenState extends ConsumerState<ClinicianMoreScreen> {
  bool _uploadingAvatar = false;

  Future<void> _changeAvatar() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final source = await _pickImageSource();
    if (source == null) return;

    final XFile? file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
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
            ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(l10n.chatAttachCamera), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(l10n.chatAttachGallery), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ],
        ),
      ),
    );
  }

  Future<void> _changeLanguage(String code) async {
    await ref.read(localeControllerProvider.notifier).setLanguage(code);
    ref.read(authControllerProvider.notifier).updateLocalUserLanguage(code);
    try {
      await ref.read(authRepositoryProvider).updateMe(language: code);
    } on ApiException {
      // Local preference still applies.
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
      if (!await controller.enable(l10n.appLockPrompt)) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.appLockUnavailable)));
      }
    } else {
      await controller.disable();
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to access the clinic dashboard.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    final user = ref.watch(authControllerProvider).user;
    final currentLocale = ref.watch(localeControllerProvider);
    final lockEnabled = ref.watch(appLockProvider).enabled;
    final roleLabel = user?.role == 'doctor' ? 'Doctor' : 'Clinic staff';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Profile', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
        children: [
          // ---- Header --------------------------------------------------
          Column(
            children: [
              Semantics(
                button: true,
                label: l10n.profileChangePhoto,
                child: GestureDetector(
                  onTap: _uploadingAvatar ? null : _changeAvatar,
                  onLongPress: user?.avatarUrl != null ? () => FullscreenPhoto.show(context, user!.avatarUrl) : null,
                  child: Stack(
                    children: [
                      UserAvatar(name: user?.name ?? '', avatarUrl: user?.avatarUrl, accent: accent, size: 96),
                      if (_uploadingAvatar)
                        Positioned.fill(
                          child: ClipOval(
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.45),
                              child: const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: accent, shape: BoxShape.circle, border: Border.all(color: scheme.surface, width: 2.5)),
                          child: const Icon(Icons.photo_camera_rounded, size: 15, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(user?.name ?? roleLabel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(user?.phone ?? '', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(roleLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // ---- Appearance ----------------------------------------------
          _label(l10n.profileAppearance, scheme),
          const ThemeSelector(),
          const SizedBox(height: AppSpacing.lg),

          // ---- Language ------------------------------------------------
          _label(l10n.profileLanguage, scheme),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _LangChip(label: l10n.languageEnglish, selected: currentLocale?.languageCode == 'en', accent: accent, onTap: () => _changeLanguage('en')),
              _LangChip(label: l10n.languageBengali, selected: currentLocale?.languageCode == 'bn', accent: accent, onTap: () => _changeLanguage('bn')),
              _LangChip(label: l10n.languageHindi, selected: currentLocale?.languageCode == 'hi', accent: accent, onTap: () => _changeLanguage('hi')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ---- Account -------------------------------------------------
          ProfileSection(
            label: l10n.profileAccount,
            children: [
              ProfileRow(icon: Icons.person_outline_rounded, title: l10n.profileEditProfile, showDivider: false, onTap: () => context.push('/clinician/more/edit')),
            ],
          ),

          // ---- Clinic tools --------------------------------------------
          ProfileSection(
            label: 'Clinic tools',
            children: [
              // Messages deliberately absent: it is the first tab. A duplicate
              // here pointed at the retired DirectMessage inbox, so the same
              // word opened different data depending on where you tapped it.
              ProfileRow(icon: Icons.notification_important_outlined, title: 'Clinical alerts', onTap: () => context.push('/clinician/alerts')),
              ProfileRow(icon: Icons.reviews_outlined, title: 'Chat review', onTap: () => context.push('/clinician/chat-review')),
              ProfileRow(icon: Icons.menu_book_outlined, title: 'Knowledge base', showDivider: false, onTap: () => context.push('/clinician/knowledge')),
            ],
          ),

          // ---- Security ------------------------------------------------
          _label(l10n.profileSecurity, scheme),
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

          // ---- Clinic --------------------------------------------------
          ProfileSection(
            label: l10n.profileClinic,
            children: [
              ProfileRow(icon: Icons.phone_outlined, title: l10n.profileCallClinic, trailingIcon: Icons.open_in_new_rounded, onTap: () => launchUrl(Uri(scheme: 'tel', path: AppConfig.clinicPhoneNumber))),
              ProfileRow(
                icon: Icons.info_outline_rounded,
                title: l10n.profileAbout,
                value: 'v${AppConfig.appVersion}',
                showDivider: false,
                onTap: () => showAboutDialog(context: context, applicationName: AppConfig.appName, applicationVersion: 'v${AppConfig.appVersion}'),
              ),
            ],
          ),

          // ---- Logout --------------------------------------------------
          SizedBox(
            width: double.infinity,
            height: AppSpacing.minTapTarget + 8,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger, width: 1.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.buttonRadius)),
              ),
              onPressed: _confirmLogout,
              icon: const Icon(Icons.logout_rounded, size: 22),
              label: Text(l10n.profileLogout, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(child: Text('ClinQ v${AppConfig.appVersion}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
        ],
      ),
    );
  }

  Widget _label(String text, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: scheme.onSurfaceVariant),
    ),
  );
}

class _LangChip extends StatelessWidget {
  const _LangChip({required this.label, required this.selected, required this.accent, required this.onTap});

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
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? accent : scheme.outlineVariant, width: selected ? 1.5 : 1),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(label, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? accent : scheme.onSurface)),
          ),
        ),
      ),
    );
  }
}

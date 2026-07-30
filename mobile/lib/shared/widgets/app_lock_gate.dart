import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../l10n/gen/app_localizations.dart';
import '../providers/app_lock_provider.dart';
import 'app_logo.dart';

/// Wraps the app: when app lock is enabled and the app is locked, it covers
/// everything with an unlock screen and re-locks whenever the app is
/// backgrounded. When lock is off, it is a transparent pass-through.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock the moment the app leaves the foreground, so a glance at the
    // recents view or a handed-over phone shows nothing.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ref.read(appLockProvider.notifier).lock();
    } else if (state == AppLifecycleState.resumed) {
      final lock = ref.read(appLockProvider);
      if (lock.enabled && lock.locked) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
      }
    }
  }

  Future<void> _unlock() async {
    if (_prompting) return;
    _prompting = true;
    final reason = AppLocalizations.of(context).appLockPrompt;
    await ref.read(appLockProvider.notifier).unlock(reason);
    _prompting = false;
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(appLockProvider);
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        widget.child,
        if (lock.enabled && lock.locked)
          // Opaque cover so nothing behind it is visible or interactive.
          //
          // Wrapped in Material, not a bare ColoredBox. This overlay sits above
          // the router rather than inside a Scaffold, so its text had no
          // Material ancestor — which is what Flutter renders as red glyphs
          // with yellow double underlines. It looked like a broken design; it
          // was actually the framework's missing-Material warning.
          Positioned.fill(
            child: Material(
              color: scheme.surface,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      const AppLogo(size: 84, showShadow: true),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        l10n.appLockLocked,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.appLockSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _unlock,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.lock_open_rounded, size: 20),
                          label: Text(l10n.appLockUnlock),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

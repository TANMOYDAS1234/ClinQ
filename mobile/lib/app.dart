import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/gen/app_localizations.dart';
import 'shared/providers/locale_provider.dart';
import 'core/push/push_service.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/widgets/app_lock_gate.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Register this device for push once someone is signed in, and detach the
    // token on sign-out. A token is only meaningful when the server knows whose
    // device it is, and leaving it attached would send the next person to use a
    // shared phone the previous patient's clinical notifications.
    ref.listen(authControllerProvider, (previous, next) {
      final wasAuthed = previous?.user != null;
      final isAuthed = next.user != null;
      if (!wasAuthed && isAuthed) {
        ref.read(pushServiceProvider).start();
      } else if (wasAuthed && !isAuthed) {
        ref.read(pushServiceProvider).stop();
      }
    });

    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeControllerProvider);
    // Watching both here is what makes appearance and language change across
    // every screen at once: MaterialApp rebuilds and the new theme and locale
    // propagate down the whole tree, including screens already on the stack.
    final themeMode = ref.watch(themeControllerProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      routerConfig: router,
      // The lock gate sits above every route, so it covers the whole app when
      // locked. `child` is the router's current page.
      builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

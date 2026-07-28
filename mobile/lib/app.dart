import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/call/call_signaling.dart';
import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/gen/app_localizations.dart';
import 'shared/providers/locale_provider.dart';
import 'core/push/push_service.dart';
import 'features/auth/presentation/auth_controller.dart';
import 'features/medications/presentation/medications_providers.dart';
import 'shared/providers/theme_provider.dart';
import 'shared/services/notification_service.dart';
import 'shared/widgets/app_lock_gate.dart';

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
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
    // Coming back to the app, pull the latest medications and rebuild the
    // reminders — so a medicine the doctor just prescribed starts reminding
    // without the patient having to open the Track screen.
    if (state == AppLifecycleState.resumed) _syncMedsIfPatient();
  }

  void _syncMedsIfPatient() {
    final user = ref.read(authControllerProvider).user;
    if (user?.role == 'patient') {
      refreshAndScheduleMedicationReminders(ref).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Register this device for push once someone is signed in, and detach the
    // token on sign-out. A token is only meaningful when the server knows whose
    // device it is, and leaving it attached would send the next person to use a
    // shared phone the previous patient's clinical notifications.
    ref.listen(authControllerProvider, (previous, next) {
      final wasAuthed = previous?.user != null;
      final isAuthed = next.user != null;
      if (!wasAuthed && isAuthed) {
        ref.read(pushServiceProvider).start();
        ref.read(callSignalingProvider).start();
        _syncMedsIfPatient();
      } else if (wasAuthed && !isAuthed) {
        ref.read(pushServiceProvider).stop();
        ref.read(callSignalingProvider).stop();
        // Clear a departing patient's dose reminders from a shared phone.
        NotificationService.instance.cancelMedicationReminders();
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

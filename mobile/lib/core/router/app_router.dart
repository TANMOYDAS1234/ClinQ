import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/care/presentation/care_placeholder_screen.dart';
import '../../features/care/presentation/care_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/onboarding/presentation/language_picker_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/shell/presentation/track_screen.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../shared/providers/locale_provider.dart';

/// Bridges Riverpod state changes into something [GoRouter]'s
/// `refreshListenable` can observe, so a login/logout or a first-time
/// language pick immediately re-runs [_redirect] without any manual
/// navigation calls from the screens themselves.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authControllerProvider, (_, _) => notifyListeners());
    ref.listen(localeControllerProvider, (_, _) => notifyListeners());
  }
}

String? _redirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authControllerProvider);
  final hasLanguage = ref.read(localeControllerProvider.notifier).hasChosenLanguage;
  final loc = state.matchedLocation;

  const splash = '/splash';
  const language = '/language';
  const login = '/login';
  const register = '/register';
  const home = '/home';

  final isAuthRoute = loc == login || loc == register;

  if (authState.status == AuthStatus.unknown) {
    return loc == splash ? null : splash;
  }

  if (!hasLanguage) {
    return loc == language ? null : language;
  }

  if (authState.status == AuthStatus.unauthenticated) {
    return isAuthRoute ? null : login;
  }

  // authenticated
  if (loc == splash || loc == language || isAuthRoute) return home;
  return null;
}

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/language', builder: (context, state) => const LanguagePickerScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (context, state) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/chat', builder: (context, state) => const ChatScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/track', builder: (context, state) => const TrackScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/care',
                builder: (context, state) => const CareScreen(),
                routes: [
                  GoRoute(
                    path: 'foot',
                    builder: (context, state) => CarePlaceholderScreen(
                      title: AppLocalizations.of(context).careFootCare,
                      icon: Icons.directions_walk_rounded,
                    ),
                  ),
                  GoRoute(
                    path: 'eye',
                    builder: (context, state) => CarePlaceholderScreen(
                      title: AppLocalizations.of(context).careEyeCare,
                      icon: Icons.visibility_outlined,
                    ),
                  ),
                  GoRoute(
                    path: 'appointments',
                    builder: (context, state) => CarePlaceholderScreen(
                      title: AppLocalizations.of(context).careAppointments,
                      icon: Icons.event_available_outlined,
                    ),
                  ),
                  GoRoute(
                    path: 'prescriptions',
                    builder: (context, state) => CarePlaceholderScreen(
                      title: AppLocalizations.of(context).carePrescriptions,
                      icon: Icons.receipt_long_outlined,
                    ),
                  ),
                  GoRoute(
                    path: 'labs',
                    builder: (context, state) => CarePlaceholderScreen(
                      title: AppLocalizations.of(context).careLabReports,
                      icon: Icons.science_outlined,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

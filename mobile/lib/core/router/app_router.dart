import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/appointments/domain/clinic.dart';
import '../../features/appointments/presentation/book_appointment_screen.dart';
import '../../features/clinician/domain/knowledge_chunk.dart';
import '../../features/appointments/presentation/my_appointments_screen.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/care/presentation/care_placeholder_screen.dart';
import '../../features/care/presentation/care_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/clinician/presentation/alerts_screen.dart';
import '../../features/clinician/presentation/appointments_admin_screen.dart';
import '../../features/clinician/presentation/chat_review_detail_screen.dart';
import '../../features/clinician/presentation/chat_review_screen.dart';
import '../../features/clinician/presentation/clinic_edit_screen.dart';
import '../../features/clinician/presentation/clinician_more_screen.dart';
import '../../features/clinician/presentation/clinician_shell.dart';
import '../../features/clinician/presentation/clinics_screen.dart';
import '../../features/clinician/presentation/dashboard_screen.dart' as clinician;
import '../../features/clinician/presentation/knowledge_edit_screen.dart';
import '../../features/clinician/presentation/knowledge_screen.dart';
import '../../features/clinician/presentation/patient_detail_screen.dart';
import '../../features/clinician/presentation/patient_thread_screen.dart';
import '../../features/clinician/presentation/patients_screen.dart';
import '../../features/messaging/presentation/clinic_chat_screen.dart';
import '../../features/messaging/presentation/clinician_messages_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/onboarding/presentation/language_picker_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/health_details_screen.dart';
import '../../features/profile/presentation/notifications_screen.dart';
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

/// The root navigator, so an incoming-call dialog can be shown over whatever
/// screen is on top from outside the widget tree (a push message handler).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

bool _isClinician(AuthState s) => s.user?.role == 'doctor' || s.user?.role == 'staff';

String? _redirect(Ref ref, GoRouterState state) {
  final authState = ref.read(authControllerProvider);
  final hasLanguage = ref.read(localeControllerProvider.notifier).hasChosenLanguage;
  final loc = state.matchedLocation;

  const splash = '/splash';
  const language = '/language';
  const login = '/login';
  const register = '/register';
  const home = '/home';
  const clinicianHome = '/clinician';

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

  // Authenticated. Doctors and staff live in the clinician area; patients in
  // the main app. Each is kept out of the other's tree.
  final inClinicianArea = loc.startsWith('/clinician');
  if (_isClinician(authState)) {
    return inClinicianArea ? null : clinicianHome;
  }
  if (inClinicianArea) return home;
  if (loc == splash || loc == language || isAuthRoute) return home;
  return null;
}

final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refreshNotifier,
    redirect: (context, state) => _redirect(ref, state),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/language', builder: (context, state) => const LanguagePickerScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),

      // Clinical-alert triage, chat review and knowledge curation are pushed
      // over the clinician shell from several places, so they live at the root.
      GoRoute(path: '/clinician/alerts', builder: (context, state) => const AlertsScreen()),
      GoRoute(path: '/clinician/chat-review', builder: (context, state) => const ChatReviewScreen()),
      GoRoute(
        path: '/clinician/chat-review/:id',
        builder: (context, state) => ChatReviewDetailScreen(sessionId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/clinician/knowledge', builder: (context, state) => const KnowledgeScreen()),
      GoRoute(path: '/clinician/knowledge/new', builder: (context, state) => const KnowledgeEditScreen()),
      GoRoute(
        path: '/clinician/knowledge/edit',
        builder: (context, state) => KnowledgeEditScreen(chunk: state.extra as KnowledgeChunk?),
      ),
      GoRoute(path: '/clinician/messages', builder: (context, state) => const ClinicianMessagesScreen()),
      // Messaging a patient opens their real conversation — the same thread the
      // patient reads on their Care Team screen — rather than a clinic-only
      // inbox holding a different half of the exchange.
      GoRoute(
        path: '/clinician/patients/:id/thread',
        builder: (context, state) => PatientThreadScreen(
          patientId: state.pathParameters['id']!,
          patientName: state.extra as String?,
        ),
      ),

      // ---- Patient app --------------------------------------------------
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
                    builder: (context, state) => const MyAppointmentsScreen(),
                    routes: [
                      GoRoute(
                        path: 'book',
                        builder: (context, state) => const BookAppointmentScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'messages',
                    builder: (context, state) => const ClinicChatScreen(),
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
                  GoRoute(path: 'edit', builder: (context, state) => const EditProfileScreen()),
                  GoRoute(path: 'health', builder: (context, state) => const HealthDetailsScreen()),
                  GoRoute(path: 'notifications', builder: (context, state) => const NotificationsScreen()),
                ],
              ),
            ],
          ),
        ],
      ),

      // ---- Clinician app (doctor + staff) -------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => ClinicianShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/clinician', builder: (context, state) => const clinician.ClinicianDashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/clinician/appointments', builder: (context, state) => const AppointmentsAdminScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/clinician/patients',
                builder: (context, state) => const PatientsScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (context, state) => PatientDetailScreen(patientId: state.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/clinician/clinics',
                builder: (context, state) => const ClinicsScreen(),
                routes: [
                  GoRoute(path: 'new', builder: (context, state) => const ClinicEditScreen()),
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) => ClinicEditScreen(clinic: state.extra as Clinic?),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/clinician/more',
                builder: (context, state) => const ClinicianMoreScreen(),
                routes: [
                  GoRoute(path: 'edit', builder: (context, state) => const EditProfileScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

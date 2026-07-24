import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_controller.dart';

/// The patient's diabetes type, read from `GET /auth/me`.
///
/// Kept out of [AuthState] because it is clinical data on `PatientProfile`,
/// not part of the authentication session — and because it changes
/// independently of login.
///
/// Returns null when the profile has no value, which the UI shows as
/// "Not set" rather than inventing one. That distinction matters: the server
/// defaults an unanswered registration to `type2`, so a displayed "Type 2"
/// may be an assumption rather than the patient's answer.
final diabetesTypeProvider = FutureProvider<String?>((ref) async {
  // Re-fetch whenever the session changes, so a different patient never sees
  // the previous one's value.
  final auth = ref.watch(authControllerProvider);
  if (!auth.isAuthenticated) return null;

  final result = await ref.read(authRepositoryProvider).getMe();
  return result.diabetesType;
});

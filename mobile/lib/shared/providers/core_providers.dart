import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/secure_store.dart';
import '../../features/auth/presentation/auth_controller.dart';

/// Overridden in `main.dart` with the awaited instance before `runApp`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden in main()');
});

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

/// Bearer header for owner-only image endpoints (`/uploads/:id/raw`), so an
/// `Image.network` can fetch protected photos.
///
/// Deliberately NOT cached for the session. Access tokens live 30 minutes and
/// Dio rotates them underneath; a header captured at sign-in is a dead token
/// well before the app is closed. Because `Image.network` bypasses Dio, it
/// cannot benefit from the refresh-and-retry interceptor — it just receives a
/// 401 and falls back to the initial, so a profile photo quietly stopped
/// appearing half an hour in. [apiClientProvider] invalidates this whenever the
/// token is rotated, so the next read picks up the live one.
final imageAuthHeaderProvider = FutureProvider<Map<String, String>>((ref) async {
  // Re-read on every auth change — a fresh sign-in, a sign-out, or replaceUser
  // after a profile edit. Without this the header could stay cached as the empty
  // map captured before sign-in, so a just-uploaded avatar never appeared (it
  // fell back to the initial) until the token happened to rotate. Watching auth
  // is what makes the new photo show up instantly.
  ref.watch(authControllerProvider);
  final token = await ref.watch(secureStoreProvider).readAccessToken();
  return token == null ? {} : {'Authorization': 'Bearer $token'};
});

/// The single Dio-backed client every repository depends on. Wires the
/// refresh-expired callback back into [authControllerProvider] so that a
/// failed silent-refresh anywhere in the app immediately drops the user to
/// the login screen via the router's redirect logic.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final secureStore = ref.watch(secureStoreProvider);
  return ApiClient(
    secureStore: secureStore,
    onAuthExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
    // Drop the cached image header the moment the token behind it is replaced.
    onTokensRefreshed: () => ref.invalidate(imageAuthHeaderProvider),
  );
});

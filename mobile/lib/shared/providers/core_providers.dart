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

/// The single Dio-backed client every repository depends on. Wires the
/// refresh-expired callback back into [authControllerProvider] so that a
/// failed silent-refresh anywhere in the app immediately drops the user to
/// the login screen via the router's redirect logic.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  final secureStore = ref.watch(secureStoreProvider);
  return ApiClient(
    secureStore: secureStore,
    onAuthExpired: () => ref.read(authControllerProvider.notifier).sessionExpired(),
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core_providers.dart';

class AppLockState {
  const AppLockState({this.enabled = false, this.locked = false});

  /// Whether the patient has turned app lock on (persisted).
  final bool enabled;

  /// Whether the app is currently locked (runtime — true on launch/resume when
  /// enabled, until a successful unlock).
  final bool locked;

  AppLockState copyWith({bool? enabled, bool? locked}) =>
      AppLockState(enabled: enabled ?? this.enabled, locked: locked ?? this.locked);
}

/// Optional biometric / device-credential lock over the whole app — meaningful
/// for a health app on a shared phone. Uses the platform prompt (fingerprint,
/// face, or the device PIN as fallback); no PIN is stored by the app itself.
class AppLockController extends StateNotifier<AppLockState> {
  AppLockController(this._prefs)
      : super(AppLockState(
          enabled: _prefs.getBool(_key) ?? false,
          // If lock is on, start locked so a fresh launch requires unlocking.
          locked: _prefs.getBool(_key) ?? false,
        ));

  final SharedPreferences _prefs;
  final LocalAuthentication _auth = LocalAuthentication();
  static const _key = 'akd_app_lock';

  Future<bool> canUse() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    }
  }

  /// Enabling requires one successful authentication, so a patient can never
  /// lock themselves out with a method that does not work on their phone.
  Future<bool> enable(String reason) async {
    if (!await _authenticate(reason)) return false;
    state = state.copyWith(enabled: true, locked: false);
    await _prefs.setBool(_key, true);
    return true;
  }

  Future<void> disable() async {
    state = state.copyWith(enabled: false, locked: false);
    await _prefs.setBool(_key, false);
  }

  /// Called when the app goes to the background.
  void lock() {
    if (state.enabled && !state.locked) state = state.copyWith(locked: true);
  }

  Future<bool> unlock(String reason) async {
    final ok = await _authenticate(reason);
    if (ok) state = state.copyWith(locked: false);
    return ok;
  }
}

final appLockProvider = StateNotifierProvider<AppLockController, AppLockState>((ref) {
  return AppLockController(ref.watch(sharedPreferencesProvider));
});

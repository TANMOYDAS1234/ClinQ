import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Central place for environment-dependent configuration.
///
/// The backend listens on port 4000. How the app reaches it depends on where
/// it is running:
///
///   * Android emulator — `localhost` is the emulator's own network namespace,
///     so the host machine is reached via the alias `10.0.2.2`.
///   * Physical Android device over USB — run `adb reverse tcp:4000 tcp:4000`
///     first, which tunnels the phone's `localhost:4000` to the development
///     machine. This is preferred over the LAN IP: it needs no Wi-Fi and no
///     firewall exception.
///   * Physical device over Wi-Fi, or a staging server — pass the URL in
///     explicitly, no code change required:
///
///       flutter run --dart-define=API_BASE_URL=http://192.168.1.9:4000/api/v1
///
/// The explicit override always wins so that release builds can be pointed at
/// a real HTTPS backend without touching this file.
class AppConfig {
  AppConfig._();

  static const String _apiPath = '/api/v1';
  static const int _port = 4000;

  /// Build-time override. Empty when not supplied.
  static const String _apiBaseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Set to true when running on a physical Android device reached through
  /// `adb reverse`, so that `localhost` is used instead of the emulator alias:
  ///
  ///     flutter run --dart-define=USE_ADB_REVERSE=true
  static const bool _useAdbReverse = bool.fromEnvironment('USE_ADB_REVERSE');

  /// Base URL for all API calls, already including the `/api/v1` prefix.
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    return 'http://$_host:$_port$_apiPath';
  }

  static String get _host {
    if (kIsWeb) return 'localhost';
    try {
      // On a physical device adb reverse makes localhost the right answer;
      // only the emulator needs the 10.0.2.2 alias.
      if (Platform.isAndroid) return _useAdbReverse ? 'localhost' : '10.0.2.2';
    } catch (_) {
      // Platform is unavailable on some targets (e.g. tests) — fall back.
    }
    return 'localhost';
  }

  /// Connection/receive timeouts for Dio.
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  static const String appName = 'ClinQ';

  /// Shown in Profile → About. Kept in step with `version:` in pubspec.yaml.
  static const String appVersion = '1.0.0';

  /// Clinic contact number used by the emergency chat card's "Call clinic"
  /// button. Not part of API_CONTRACT.md (no endpoint exposes clinic
  /// contact details) — placeholder pending a real number from the clinic;
  /// swap before release.
  static const String clinicPhoneNumber = '+913322345678';
}

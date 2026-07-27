import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/core_providers.dart';

/// Registers this device for push and keeps its token current on the server.
///
/// Delivery matters more here than in most apps: the same channel carries a
/// medication reminder and the alert that a patient has reported chest pain.
/// So registration failures are logged and retried on the next launch rather
/// than being allowed to fail silently.
class PushService {
  PushService(this._ref);

  final Ref _ref;
  StreamSubscription<String>? _tokenRefresh;

  /// Called once the user is signed in — a token is only useful when the
  /// server knows whose device it belongs to.
  Future<void> start() async {
    final messaging = FirebaseMessaging.instance;

    // Android 13+ requires this at runtime. Declining is a legitimate choice;
    // the app must keep working, so the result is recorded and not enforced.
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('push: permission denied — notifications will not arrive');
      return;
    }

    final token = await messaging.getToken();
    if (token != null) await _register(token);

    // FCM rotates tokens on reinstall, restore and occasionally on its own. A
    // stale token silently swallows every notification, so the rotation is
    // followed rather than read once at startup.
    _tokenRefresh?.cancel();
    _tokenRefresh = messaging.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    try {
      await _ref.read(apiClientProvider).postJson('/auth/device-token', body: {'token': token});
    } catch (e) {
      // Not fatal: the next launch re-registers. Worth logging, because a
      // patient whose token never registers simply stops receiving alerts and
      // nothing else would reveal it.
      debugPrint('push: could not register device token — $e');
    }
  }

  /// Detaches the token on sign-out so the next person to use this device does
  /// not receive the previous patient's clinical notifications.
  Future<void> stop() async {
    await _tokenRefresh?.cancel();
    _tokenRefresh = null;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _ref.read(apiClientProvider).delete('/auth/device-token', body: {'token': token});
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('push: could not detach device token — $e');
    }
  }
}

final pushServiceProvider = Provider<PushService>((ref) => PushService(ref));

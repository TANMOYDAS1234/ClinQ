import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../shared/providers/core_providers.dart';
import '../../shared/services/notification_service.dart';
import '../router/app_router.dart';

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
  StreamSubscription<RemoteMessage>? _onMessage;
  StreamSubscription<RemoteMessage>? _onOpened;

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

    _wireNotificationHandlers();
  }

  /// Wires the three ways a notification reaches a signed-in app: foreground
  /// (Android won't show it, so we do), a tap that resumed the app, and a tap
  /// that cold-started it. Re-runnable — subscriptions are replaced, not stacked.
  void _wireNotificationHandlers() {
    NotificationService.instance.onNotificationTap = _routeFromPayload;

    // Foreground: FCM does not display a notification while the app is open, so
    // surface it ourselves and carry the routing data as the tap payload.
    _onMessage?.cancel();
    _onMessage = FirebaseMessaging.onMessage.listen((m) {
      // Data-only medication reminder: render it with the SAME id as the local
      // alarm so the two collapse instead of double-reminding.
      if (m.data['kind'] == 'medication_reminder') {
        final id = int.tryParse(m.data['notifId']?.toString() ?? '');
        if (id != null) {
          NotificationService.instance.showMedicationReminder(
            id: id,
            name: m.data['name']?.toString() ?? 'your medicine',
            medId: m.data['medicationId']?.toString(),
            dose: m.data['dose']?.toString(),
            relationToMeal: m.data['relationToMeal']?.toString(),
            time: m.data['time']?.toString(),
          );
        }
        return;
      }
      final n = m.notification;
      if (n == null) return;
      NotificationService.instance.show(
        title: n.title ?? 'ClinQ',
        body: n.body ?? '',
        payload: jsonEncode(m.data),
      );
    });

    // A tap that brought the app back from the background.
    _onOpened?.cancel();
    _onOpened = FirebaseMessaging.onMessageOpenedApp.listen((m) => _routeFromData(m.data));

    // A tap that cold-started the app from a terminated state. Delayed a beat so
    // the post-login route settles before the conversation is pushed on top.
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) {
        Future.delayed(const Duration(milliseconds: 700), () => _routeFromData(m.data));
      }
    });
  }

  void _routeFromPayload(String payload) {
    // Medication reminders carry a "med:<id>" payload, not routable JSON.
    if (payload.startsWith('med:')) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _routeFromData(decoded.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (_) {
      // Not a routable payload — ignore rather than crash on a tap.
    }
  }

  /// Opens the conversation a notification is about. A patient only ever gets a
  /// clinician reply, so their tap opens their own chat; a clinician's tap opens
  /// the patient thread the alert or message named (or the alert list if none).
  void _routeFromData(Map<String, dynamic> data) {
    final user = _ref.read(authControllerProvider).user;
    if (user == null) return;
    final router = _ref.read(appRouterProvider);

    if (user.role == 'patient') {
      // A prescription update opens Medicines; everything else opens the chat.
      final kind = data['kind']?.toString();
      router.go(kind == 'prescription' ? '/medications' : '/chat');
      return;
    }
    final patientId = data['patientId']?.toString();
    if (patientId != null && patientId.isNotEmpty) {
      router.push('/clinician/patients/$patientId/thread');
    } else {
      router.push('/clinician/alerts');
    }
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
    await _onMessage?.cancel();
    _onMessage = null;
    await _onOpened?.cancel();
    _onOpened = null;
    NotificationService.instance.onNotificationTap = null;
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

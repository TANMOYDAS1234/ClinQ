import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/auth_controller.dart';
import '../../l10n/gen/app_localizations.dart';
import '../router/app_router.dart';
import '../theme/app_colors.dart';
import 'call_service.dart';

/// Listens for `incoming_call` push messages and turns them into a ringing
/// screen. Accepting joins the same Jitsi room the caller is already in.
///
/// Foreground: shows an accept/decline dialog. Background/terminated: the FCM
/// notification shows on the lock screen, and tapping it counts as accepting.
class CallSignaling {
  CallSignaling(this._ref);

  final Ref _ref;
  StreamSubscription<RemoteMessage>? _fg;
  StreamSubscription<RemoteMessage>? _opened;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _fg = FirebaseMessaging.onMessage.listen(_onForeground);
    _opened = FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
    // The app may have been launched by tapping the call notification.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _onOpened(initial);
  }

  Future<void> stop() async {
    await _fg?.cancel();
    await _opened?.cancel();
    _fg = null;
    _opened = null;
    _started = false;
  }

  void _onForeground(RemoteMessage m) {
    if (m.data['type'] == 'incoming_call') _showIncoming(m.data);
  }

  void _onOpened(RemoteMessage m) {
    // Opening the app by tapping the call notification is itself an accept.
    if (m.data['type'] == 'incoming_call') _join(m.data);
  }

  void _showIncoming(Map<String, dynamic> data) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    final l10n = AppLocalizations.of(ctx);
    final caller = data['callerName']?.toString() ?? l10n.chatFromClinic;
    final video = data['video']?.toString() == 'true';

    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        icon: Icon(video ? Icons.videocam_rounded : Icons.call_rounded, color: AppColors.primary, size: 40),
        title: Text('$caller · ${video ? l10n.callVideo : l10n.callVoice}'),
        content: Text(l10n.callStart),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n.commonNo, style: const TextStyle(color: AppColors.danger)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _join(data);
            },
            child: Text(l10n.commonYes),
          ),
        ],
      ),
    );
  }

  Future<void> _join(Map<String, dynamic> data) async {
    final room = data['room']?.toString();
    if (room == null || room.isEmpty) return;
    final name = _ref.read(authControllerProvider).user?.name ?? 'ClinQ';
    final video = data['video']?.toString() == 'true';
    try {
      await CallService.instance.start(room: room, displayName: name, video: video);
    } catch (_) {
      // Nothing more to do — the caller will notice they are alone in the room.
    }
  }
}

final callSignalingProvider = Provider<CallSignaling>((ref) => CallSignaling(ref));

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/providers/core_providers.dart';
import 'call_service.dart';

/// App-bar call control: tap to choose a video or voice call into [room]. It
/// rings the other side (a push alert) and joins the Jitsi room; inside, the
/// camera can be toggled, so voice ↔ video at any time.
class CallButton extends ConsumerWidget {
  const CallButton({
    super.key,
    required this.room,
    required this.displayName,
    required this.patientId,
  });

  final String room;
  final String displayName;

  /// The patient whose thread this call belongs to — used to ring the other
  /// side. The server ignores it for a patient (it uses their own id).
  final String patientId;

  Future<void> _call(BuildContext context, WidgetRef ref, bool video) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Ring the other side first — best-effort, so a call still connects if the
    // push provider is down (the other party can also just tap call).
    try {
      await ref.read(apiClientProvider).postJson('/calls/ring', body: {'patientId': patientId, 'video': video});
    } catch (_) {
      // Non-fatal.
    }

    try {
      await CallService.instance.start(room: room, displayName: displayName, video: video);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.callFailed)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<bool>(
      icon: const Icon(Icons.videocam_rounded),
      tooltip: l10n.callStart,
      onSelected: (video) => _call(context, ref, video),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: true,
          child: Row(children: [const Icon(Icons.videocam_outlined), const SizedBox(width: 12), Text(l10n.callVideo)]),
        ),
        PopupMenuItem(
          value: false,
          child: Row(children: [const Icon(Icons.call_outlined), const SizedBox(width: 12), Text(l10n.callVoice)]),
        ),
      ],
    );
  }
}

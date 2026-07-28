import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';
import 'call_service.dart';

/// App-bar call control: tap to choose a video or voice call into [room].
/// Inside the call the camera can be toggled, so voice ↔ video at any time.
class CallButton extends StatelessWidget {
  const CallButton({super.key, required this.room, required this.displayName});

  final String room;
  final String displayName;

  Future<void> _call(BuildContext context, bool video) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await CallService.instance.start(room: room, displayName: displayName, video: video);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.callFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<bool>(
      icon: const Icon(Icons.videocam_rounded),
      tooltip: l10n.callStart,
      onSelected: (video) => _call(context, video),
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

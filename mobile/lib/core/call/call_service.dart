import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

import '../config/app_config.dart';

/// In-app voice/video calling over Jitsi. Both the patient and the clinic join
/// the same deterministic room, so either can start the call and the other
/// lands in the same conference. Inside, the camera can be toggled at any time
/// (voice ↔ video).
///
/// The UI is deliberately stripped to a 1:1 consultation: full-screen remote
/// video, a small self-view, and only mic / camera / flip / hang-up. Everything
/// a public meeting has and a clinic call does not — chat, tile view, screen
/// share, invite, reactions, the overflow menu — is turned off, so it reads as
/// a native call rather than a Jitsi meeting.
///
/// Server comes from [AppConfig.jitsiServerUrl] — a self-hosted instance, so
/// patient video stays on the clinic's own infrastructure and there is no
/// meet.jit.si moderator-login gate.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final JitsiMeet _jitsi = JitsiMeet();

  /// The room a patient and their clinic share. Both sides derive the same
  /// string from the patient's id, so no room needs to be exchanged.
  static String roomForPatient(String patientId) => 'clinq-care-$patientId';

  /// Starts (or joins) the call. [video] false starts as a voice call; the
  /// camera can still be turned on mid-call.
  Future<void> start({
    required String room,
    required String displayName,
    bool video = true,
  }) async {
    final options = JitsiMeetConferenceOptions(
      serverURL: AppConfig.jitsiServerUrl,
      room: room,
      configOverrides: {
        'startWithAudioMuted': false,
        'startWithVideoMuted': !video,
        'subject': 'ClinQ consultation',
        // No "open in browser/app" interstitial — go straight into the call.
        'disableDeepLinking': true,
        // Skip the pre-join preview; the call opens immediately.
        'prejoinConfig': {'enabled': false},
        'disableInviteFunctions': true,
        // A 1:1 call has no grid to switch to.
        'disableTileView': true,
        'hideConferenceTimer': true,
        // The only controls a consultation needs. This whitelist is what keeps
        // the toolbar clean — every other button is simply absent.
        'toolbarButtons': ['microphone', 'camera', 'toggle-camera', 'hangup'],
      },
      featureFlags: {
        'welcomepage.enabled': false,
        'prejoinpage.enabled': false,
        // Never leave a patient stuck in a "waiting for a moderator" lobby.
        'lobby-mode.enabled': false,
        // A clinical call is 1:1 with the clinic — no inviting strangers.
        'invite.enabled': false,
        'add-people.enabled': false,
        // Messaging lives in the app's own chat, not here.
        'chat.enabled': false,
        'raise-hand.enabled': false,
        'reactions.enabled': false,
        'tile-view.enabled': false,
        'screen-sharing.enabled': false,
        'video-share.enabled': false,
        'recording.enabled': false,
        'live-streaming.enabled': false,
        'calendar.enabled': false,
        'close-captions.enabled': false,
        'kick-out.enabled': false,
        'meeting-name.enabled': false,
        'meeting-password.enabled': false,
        'security-options.enabled': false,
        'server-url-change.enabled': false,
        'settings.enabled': false,
        'video-quality.enabled': false,
        'overflow-menu.enabled': false,
        'help.enabled': false,
        // Keep it fully in-app rather than handing off to the system phone UI.
        'call-integration.enabled': false,
        'pip.enabled': true,
      },
      userInfo: JitsiMeetUserInfo(displayName: displayName),
    );
    await _jitsi.join(options);
  }
}

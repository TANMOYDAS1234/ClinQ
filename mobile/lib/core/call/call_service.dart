import 'package:jitsi_meet_flutter_sdk/jitsi_meet_flutter_sdk.dart';

/// In-app voice/video calling over Jitsi. Both the patient and the clinic join
/// the same deterministic room, so either can start the call and the other
/// lands in the same conference. Inside, the camera can be toggled at any time
/// (voice ↔ video).
///
/// Uses Jitsi's public server for now; point [_server] at a self-hosted Jitsi
/// on the VPS for full privacy without changing anything else.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  final JitsiMeet _jitsi = JitsiMeet();

  static const String _server = 'https://meet.jit.si';

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
      serverURL: _server,
      room: room,
      configOverrides: {
        'startWithAudioMuted': false,
        'startWithVideoMuted': !video,
        'subject': 'ClinQ consultation',
      },
      featureFlags: {
        'welcomepage.enabled': false,
        'prejoinpage.enabled': false,
        // A clinical call is 1:1 with the clinic — no inviting strangers.
        'invite.enabled': false,
        'raise-hand.enabled': false,
      },
      userInfo: JitsiMeetUserInfo(displayName: displayName),
    );
    await _jitsi.join(options);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'voice_input_sheet.dart' show kVoiceLocales;

enum VoiceStatus { idle, listening, denied, unavailable, done }

/// Owns the on-device speech lifecycle independently of any UI container, so
/// both the tap-to-review sheet and the hold-to-talk overlay can drive it.
///
/// Transcription is deliberate: the triage engine reads text, and a number
/// here is a blood sugar reading, so speech is always turned into text the
/// patient can see — never sent as audio the rules would never match.
class VoiceRecognizer extends ChangeNotifier {
  VoiceRecognizer(this._languageCode);

  final SpeechToText _speech = SpeechToText();
  final String _languageCode;

  VoiceStatus status = VoiceStatus.idle;
  String finalWords = '';
  String partialWords = '';

  /// Smoothed 0..1 microphone level, and a short rolling history for the
  /// waveform.
  double level = 0;
  final List<double> levels = List<double>.filled(28, 0.06, growable: true);

  Duration elapsed = Duration.zero;
  Timer? _ticker;
  Stopwatch? _stopwatch;

  String get transcript => (finalWords.isNotEmpty ? finalWords : partialWords).trim();

  Future<void> start() async {
    final available = await _speech.initialize(
      onError: (_) {
        if (status == VoiceStatus.listening && transcript.isEmpty) {
          status = VoiceStatus.done;
          notifyListeners();
        }
      },
      onStatus: (_) {},
    );

    if (!available) {
      final granted = await _speech.hasPermission;
      status = granted ? VoiceStatus.unavailable : VoiceStatus.denied;
      notifyListeners();
      return;
    }

    finalWords = '';
    partialWords = '';
    elapsed = Duration.zero;
    status = VoiceStatus.listening;
    // Stopwatch rather than wall-clock arithmetic, so a clock change mid-record
    // cannot make the timer jump.
    _stopwatch = Stopwatch()..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      elapsed = _stopwatch?.elapsed ?? Duration.zero;
      notifyListeners();
    });
    notifyListeners();

    final locale = kVoiceLocales[_languageCode]?.localeId ?? 'en_IN';
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        cancelOnError: false,
        // Cloud recogniser: markedly more accurate, especially for numbers and
        // for Bengali/Hindi. Falls back to on-device when offline.
        onDevice: false,
        autoPunctuation: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(minutes: 2),
      ),
      onResult: (r) {
        if (r.finalResult) {
          finalWords = r.recognizedWords;
          partialWords = '';
        } else {
          partialWords = r.recognizedWords;
        }
        notifyListeners();
      },
      onSoundLevelChange: (raw) {
        final normalised = ((raw + 2) / 12).clamp(0.06, 1.0);
        level = level + (normalised - level) * 0.4;
        levels.add(level);
        if (levels.length > 28) levels.removeAt(0);
        notifyListeners();
      },
    );
  }

  /// Stop and keep the transcript.
  Future<String?> stop() async {
    _ticker?.cancel();
    _stopwatch?.stop();
    await _speech.stop();
    status = VoiceStatus.done;
    notifyListeners();
    final t = transcript;
    return t.isEmpty ? null : t;
  }

  /// Abandon and discard.
  Future<void> abort() async {
    _ticker?.cancel();
    _stopwatch?.stop();
    await _speech.cancel();
    status = VoiceStatus.done;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_speech.cancel());
    super.dispose();
  }
}

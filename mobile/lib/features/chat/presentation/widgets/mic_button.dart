import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/theme/app_colors.dart';

/// Locale the recogniser listens in, preferring the Indian variant for each
/// app language — Indian-accented English and native Bengali/Hindi.
const Map<String, String> _recogniserLocales = {
  'en': 'en_IN',
  'bn': 'bn_IN',
  'hi': 'hi_IN',
};

/// Tap-to-dictate microphone that lives inside the composer pill.
///
/// Idle it is an outline icon. Listening, it becomes a filled red circle that
/// emits two expanding rings and a halo that swells with live mic loudness.
/// Recognised words are handed back through [onWords] to be **appended** to the
/// field — dictation never overwrites what was typed. Speech is transcribed to
/// text on purpose: the triage rules read text, and a number here is a blood
/// sugar reading the patient must see before sending.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.languageCode,
    required this.onWords,
    this.onListeningChanged,
    this.onUnavailable,
    this.size = 44,
  });

  final String languageCode;

  /// Final recognised words for this utterance, to append to the field.
  final ValueChanged<String> onWords;

  /// Fires true when listening starts, false when it ends — the composer uses
  /// this to light up the animated border.
  final ValueChanged<bool>? onListeningChanged;

  /// Called with a human-readable reason when the mic cannot be used.
  final ValueChanged<String>? onUnavailable;

  final double size;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();
  bool _initialised = false;
  bool _listening = false;

  /// Smoothed 0..1 loudness. A ValueNotifier so the halo repaints on its own,
  /// without rebuilding the text field beside it.
  final ValueNotifier<double> _level = ValueNotifier(0);

  late final AnimationController _rings;

  @override
  void initState() {
    super.initState();
    _rings = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  }

  @override
  void dispose() {
    _rings.dispose();
    _level.dispose();
    _speech.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stop();
      return;
    }

    // Lazy init: the permission prompt appears on the first tap, not when the
    // chat screen opens.
    if (!_initialised) {
      _initialised = await _speech.initialize(onError: (_) => _stop(), onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && _listening) _stop();
      });
    }
    if (!_initialised) {
      final granted = await _speech.hasPermission;
      widget.onUnavailable?.call(granted ? 'unavailable' : 'denied');
      return;
    }

    await HapticFeedback.mediumImpact();
    setState(() => _listening = true);
    widget.onListeningChanged?.call(true);
    _rings.repeat();

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: _recogniserLocales[widget.languageCode] ?? 'en_IN',
        partialResults: true,
        cancelOnError: false,
        onDevice: false,
        autoPunctuation: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(minutes: 2),
      ),
      onResult: (r) {
        // Append each finished utterance; keep listening for the next.
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          widget.onWords(r.recognizedWords.trim());
        }
      },
      onSoundLevelChange: (raw) {
        final normalised = ((raw + 2) / 12).clamp(0.0, 1.0);
        _level.value = _level.value + (normalised - _level.value) * 0.4;
      },
    );
  }

  Future<void> _stop() async {
    if (!_listening) return;
    await _speech.stop();
    if (!mounted) return;
    setState(() => _listening = false);
    _rings.stop();
    _level.value = 0;
    widget.onListeningChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: _listening ? 'Stop recording' : 'Speak',
      child: InkResponse(
        onTap: _toggle,
        radius: widget.size / 2 + 6,
        child: SizedBox(
          // 44px tap target regardless of the visual size.
          width: widget.size,
          height: widget.size,
          child: Center(
            child: _listening
                ? _listeningVisual(scheme)
                : Icon(Icons.mic_none_rounded, size: 24, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _listeningVisual(ColorScheme scheme) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Two expanding, fading rings.
          AnimatedBuilder(
            animation: _rings,
            builder: (context, _) => CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _RingsPainter(progress: _rings.value, color: AppColors.danger),
            ),
          ),
          // Halo that swells with loudness — repaints on its own.
          ValueListenableBuilder<double>(
            valueListenable: _level,
            builder: (context, level, _) => Container(
              width: 26 + level * 16,
              height: 26 + level * 16,
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // The solid red mic.
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
            child: const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final maxR = size.width / 2;
    // Two rings half a cycle apart.
    for (final phase in [0.0, 0.5]) {
      final t = (progress + phase) % 1.0;
      final r = 14 + t * (maxR - 14);
      final opacity = (1 - t) * 0.5;
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.progress != progress;
}

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Replaces the composer while a voice note is being recorded.
///
/// It takes over the whole bar rather than sitting beside the text field on
/// purpose: recording is a mode, and a patient who cannot tell whether the mic
/// is live will either send silence or say something private believing it is
/// off. The bar states the mode, counts the seconds, and offers exactly two
/// ways out — bin it, or send it.
class VoiceRecorderBar extends StatefulWidget {
  const VoiceRecorderBar({super.key, required this.onCancel, required this.onSend});

  final VoidCallback onCancel;

  /// Path to the finished recording, and how long it ran.
  final void Function(String path, Duration length) onSend;

  @override
  State<VoiceRecorderBar> createState() => _VoiceRecorderBarState();
}

class _VoiceRecorderBarState extends State<VoiceRecorderBar> {
  final _recorder = AudioRecorder();
  Timer? _ticker;
  StreamSubscription<Amplitude>? _amplitude;

  Duration _elapsed = Duration.zero;

  /// Smoothed 0..1 loudness driving the bars. Smoothed because raw amplitude
  /// jitters hard enough to look like a fault rather than a voice.
  double _level = 0;

  bool _starting = true;
  String? _path;

  /// A ceiling, not a budget.
  ///
  /// Uncompressed 16 kHz mono WAV is ~1.9 MB per minute, so a note reaches the
  /// server's 12 MB upload cap around six minutes. Stopping at five keeps even
  /// the longest note safely uploadable rather than letting a patient talk on
  /// and then lose all of it at upload — and five minutes is far beyond any real
  /// "how have you been feeling".
  static const _maxLength = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _amplitude?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        widget.onCancel();
        return;
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.wav';

      await _recorder.start(
        // WAV/PCM at 16 kHz mono. Unlike the AAC-in-MP4 (m4a) it used to record —
        // which the transcription model cannot read and which needs a fragile
        // server-side conversion — WAV is accepted directly, and PCM needs no
        // hardware codec so it records on every Android version. 16 kHz mono is
        // ample for speech and keeps a few-minute note well under the upload cap.
        // This is what makes a voice note both transcribe AND play back.
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );

      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _path = path;
        _starting = false;
      });

      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() => _elapsed += const Duration(milliseconds: 200));
        if (_elapsed >= _maxLength) _stopAndSend();
      });

      _amplitude = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
            if (!mounted) return;
            // dBFS, roughly -45 (silence) to 0 (loud).
            final normalised = ((a.current + 45) / 45).clamp(0.0, 1.0);
            setState(() => _level = _level + (normalised - _level) * 0.35);
          });
    } catch (_) {
      widget.onCancel();
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    await _recorder.stop();
    // Discard immediately rather than leaving it in the cache: a patient who
    // cancels a recording means it should not exist.
    final path = _path;
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    widget.onCancel();
  }

  Future<void> _stopAndSend() async {
    _ticker?.cancel();
    await _amplitude?.cancel();
    final path = await _recorder.stop();
    if (path == null) {
      widget.onCancel();
      return;
    }
    HapticFeedback.lightImpact();
    widget.onSend(path, _elapsed);
  }

  String get _clock {
    final m = _elapsed.inMinutes;
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.commonCancel,
                onPressed: _cancel,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.onSurfaceVariant),
              ),
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Row(
                    children: [
                      // Pulses with the voice, so it is unmistakably live.
                      _RecordingDot(level: _level),
                      const SizedBox(width: 10),
                      Text(
                        _starting ? '…' : _clock,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                          color: AppColors.danger,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: _LiveBars(level: _level)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _starting ? null : _stopAndSend,
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(Icons.send_rounded, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordingDot extends StatelessWidget {
  const _RecordingDot({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 10 + level * 6,
            height: 10 + level * 6,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 9,
            height: 9,
            decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

/// Bars that move with the voice.
///
/// Driven by live amplitude rather than a canned animation: a fake waveform
/// that dances during silence teaches patients the indicator means nothing,
/// and they stop trusting it exactly when it matters.
class _LiveBars extends StatelessWidget {
  const _LiveBars({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final count = math.max(6, (constraints.maxWidth / 6).floor());
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 3,
                  // Centre bars react most, so it reads as a voice rather than
                  // a progress bar.
                  height: 4 + level * 18 * (0.45 + 0.55 * math.sin((i / count) * math.pi)),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

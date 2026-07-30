import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/chat_message.dart';

/// Plays a voice note, and shows what was said underneath it.
///
/// The transcript is not decoration. A doctor with forty threads cannot listen
/// to every clip, a patient may be somewhere they cannot play sound, and a deaf
/// patient would otherwise be shut out of their own conversation. The audio
/// carries tone; the text carries the content.
class VoiceNotePlayer extends ConsumerStatefulWidget {
  const VoiceNotePlayer({super.key, required this.note, required this.onDark});

  final VoiceNote note;

  /// True inside the patient's own (deep green) bubble, where the controls have
  /// to invert to stay legible.
  final bool onDark;

  @override
  ConsumerState<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends ConsumerState<VoiceNotePlayer> {
  AudioPlayer? _player;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// Created on first play rather than in initState: a thread can hold dozens
  /// of notes, and one decoder per bubble would be held open for all of them.
  Future<void> _toggle() async {
    final existing = _player;
    if (existing != null) {
      if (existing.playing) {
        await existing.pause();
      } else {
        // Restarting from the end feels broken otherwise — the button does
        // nothing on a finished clip.
        if (_duration != null && _position >= _duration! - const Duration(milliseconds: 250)) {
          await existing.seek(Duration.zero);
        }
        await existing.play();
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final headers = ref.read(imageAuthHeaderProvider).valueOrNull;
      final player = AudioPlayer();
      // Uploads are owner-protected, so the bearer token travels with the
      // request exactly as it does for images.
      final duration = await player.setUrl(
        '${AppConfig.apiOrigin}${widget.note.url}',
        headers: headers,
      );

      player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      player.playerStateStream.listen((s) {
        if (mounted) setState(() {});
      });

      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _duration = duration;
        _loading = false;
      });
      await player.play();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _clock(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = widget.onDark ? Colors.white : AppColors.primary;
    final track = widget.onDark ? Colors.white24 : AppColors.primary.withValues(alpha: 0.18);

    final playing = _player?.playing ?? false;
    final total = _duration;
    final progress = (total == null || total.inMilliseconds == 0)
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: widget.onDark ? Colors.white24 : AppColors.accentSoft,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _loading ? null : _toggle,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: _loading
                        ? SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2.2, color: fg),
                          )
                        : Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            color: fg, size: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 122,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Waveform(progress: progress, colour: fg, track: track),
                  const SizedBox(height: 5),
                  Text(
                    total == null ? '' : '${_clock(_position)} / ${_clock(total)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: widget.onDark ? Colors.white70 : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (widget.note.transcript != null && widget.note.transcript!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            widget.note.transcript!,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.45,
              color: widget.onDark ? Colors.white : scheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}

/// Static bar pattern that fills as the clip plays.
///
/// Deliberately not a real amplitude waveform: computing one means decoding the
/// whole file before the first frame, which would stall a thread full of notes
/// to draw something nobody reads for its shape. This says "audio, and how far
/// through you are", which is all the bar is asked to do.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.progress, required this.colour, required this.track});

  final double progress;
  final Color colour;
  final Color track;

  static const _heights = <double>[
    7, 12, 18, 10, 22, 15, 9, 20, 26, 14, 8, 17, 23, 11, 19, 13, 25, 9, 16, 21, 12, 7,
  ];

  @override
  Widget build(BuildContext context) {
    final filled = (_heights.length * progress).round();
    return SizedBox(
      height: 26,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _heights.length; i++) ...[
            Container(
              width: 3,
              height: _heights[i],
              decoration: BoxDecoration(
                color: i < filled ? colour : track,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (i != _heights.length - 1) const SizedBox(width: 2.4),
          ],
        ],
      ),
    );
  }
}

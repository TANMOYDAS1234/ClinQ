import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

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
  const VoiceNotePlayer({
    super.key,
    required this.note,
    required this.onDark,
    this.showTranscript = true,
  });

  final VoiceNote note;

  /// True inside the patient's own (deep green) bubble, where the controls have
  /// to invert to stay legible.
  final bool onDark;

  /// Hidden on the patient's own recording — they know what they just said, so
  /// repeating it back is noise. Kept on the clinician's side, where it is the
  /// only way to skim a thread without playing every clip, and the only way a
  /// deaf reader gets the content at all.
  final bool showTranscript;

  @override
  ConsumerState<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends ConsumerState<VoiceNotePlayer> {
  AudioPlayer? _player;
  bool _loading = false;

  /// Whether the full transcript is shown, or the first three lines.
  bool _transcriptExpanded = false;
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
      // Downloaded, not streamed. just_audio needs the bearer token, and on
      // Android a header-bearing URL is served through a local proxy that is
      // unreliable over HTTPS — which is why playback silently did nothing.
      // Dio already carries and refreshes the token, and a voice note is small
      // enough that fetching it first is imperceptible.
      final dir = await getTemporaryDirectory();
      final cached = File('${dir.path}/vn_${widget.note.url.hashCode}.m4a');
      if (!await cached.exists()) {
        // Absolute URL, not the relative path. `note.url` already begins with
        // /api/v1, and Dio's baseUrl ends with it — passing the path made the
        // request go to /api/v1/api/v1/uploads/... which 404s, so the player
        // simply never started. apiOrigin is the host without the suffix.
        await ref
            .read(apiClientProvider)
            .downloadToFile('${AppConfig.apiOrigin}${widget.note.url}', cached.path);
      }

      final player = AudioPlayer();
      final duration = await player.setFilePath(cached.path);

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
    // Same hue as the play glyph, half strength — so the unplayed part of the
    // waveform reads as the same control rather than as grey filler.
    final track = widget.onDark
        ? Colors.white.withValues(alpha: 0.45)
        : AppColors.primary.withValues(alpha: 0.42);

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
          crossAxisAlignment: CrossAxisAlignment.center,
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
            const SizedBox(width: 12),
            // Waveform sits beside the button, not stacked above a timestamp.
            // With the clock in the same column the pair centred as a block, so
            // the bars floated above the button's middle instead of running
            // through it. The clock moved below the whole row.
            SizedBox(
              width: 132,
              child: _Waveform(progress: progress, colour: fg, track: track),
            ),
          ],
        ),
        if (total != null) ...[
          const SizedBox(height: 5),
          Padding(
            // Indented past the play button so it sits under the waveform.
            padding: const EdgeInsets.only(left: 52),
            child: Text(
              '${_clock(_position)} / ${_clock(total)}',
              style: TextStyle(
                fontSize: 11.5,
                color: widget.onDark ? Colors.white70 : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
        if (widget.showTranscript &&
            widget.note.transcript != null &&
            widget.note.transcript!.isNotEmpty) ...[
          const SizedBox(height: 8),
          // Collapsed to a single line. A ten-minute note transcribes to
          // hundreds of words, and a thread of those is unreadable — one line
          // says what the message is about, and the rest is a tap away.
          // Truncated rather than summarised on purpose: a summary of someone
          // describing symptoms is exactly where a dropped detail does harm.
          Text(
            widget.note.transcript!,
            maxLines: _transcriptExpanded ? null : 1,
            overflow: _transcriptExpanded ? null : TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              height: 1.45,
              color: widget.onDark ? Colors.white : scheme.onSurface,
            ),
          ),
          // Threshold roughly one line at this width; below it the toggle would
          // be offering to expand text already fully visible.
          if (widget.note.transcript!.length > 38)
            GestureDetector(
              onTap: () => setState(() => _transcriptExpanded = !_transcriptExpanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _transcriptExpanded ? 'Show less' : 'Show more',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: widget.onDark ? Colors.white70 : AppColors.primary,
                  ),
                ),
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

  /// Taller and with more spread than a decorative squiggle: the short bars
  /// were barely visible against the bubble, so the control read as an empty
  /// strip rather than as audio.
  static const _heights = <double>[
    10, 17, 26, 14, 31, 21, 12, 28, 36, 19, 11, 24, 33, 15, 27, 18, 35, 13, 22, 30, 16, 10,
  ];

  @override
  Widget build(BuildContext context) {
    final filled = (_heights.length * progress).round();
    return SizedBox(
      height: 36,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _heights.length; i++) ...[
            Container(
              width: 3.5,
              height: _heights[i],
              decoration: BoxDecoration(
                // Unplayed bars are the same green as the play glyph, just
                // faded — at 0.18 they read as grey and looked unrelated to
                // the button beside them.
                color: i < filled ? colour : track,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (i != _heights.length - 1) const SizedBox(width: 2.2),
          ],
        ],
      ),
    );
  }
}

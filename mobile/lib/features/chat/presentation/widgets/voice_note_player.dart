import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/chat_message.dart';

/// Plays a voice note, WhatsApp-style: a play/pause button, a progress waveform
/// and a clock. No transcript is shown — the recording speaks for itself.
///
/// The audio is downloaded (not streamed) because the file is owner-protected
/// and needs the bearer token; a header-bearing URL is served on Android through
/// a local proxy that is unreliable over HTTPS, so fetching the bytes through
/// Dio and playing a local file is what makes playback reliable.
class VoiceNotePlayer extends ConsumerStatefulWidget {
  const VoiceNotePlayer({super.key, required this.note, required this.onDark});

  final VoiceNote note;

  /// True inside the sender's own (deep green) bubble, where the controls invert
  /// to stay legible.
  final bool onDark;

  @override
  ConsumerState<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends ConsumerState<VoiceNotePlayer> {
  AudioPlayer? _player;
  bool _loading = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  /// The downloaded file, kept so a finished note can be reloaded and replayed.
  String? _cachedPath;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  /// Created on first play rather than in initState: a thread can hold dozens of
  /// notes, and one decoder per bubble would be held open for all of them.
  Future<void> _toggle() async {
    final existing = _player;
    if (existing != null) {
      switch (existing.state) {
        case PlayerState.playing:
          await existing.pause();
        case PlayerState.paused:
          await existing.resume();
        default:
          // Finished or stopped: reload the file and play from the start, so a
          // note can be replayed as many times as you like. A plain resume()
          // would do nothing here because the source was freed on completion —
          // reloading is what makes replay reliable.
          if (_cachedPath != null) await existing.play(DeviceFileSource(_cachedPath!));
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final dir = await getTemporaryDirectory();
      // Cache under the real extension so the decoder is picked correctly. Notes
      // arrive as audio/mpeg (MP3); older/fallback formats keep their own.
      final ext = _extForMime(widget.note.mimeType);
      final cached = File('${dir.path}/vn_${widget.note.url.hashCode}.$ext');
      _cachedPath = cached.path;
      // Re-fetch when the cache is missing OR empty — a prior failed attempt
      // could have left a 0-byte file that would never decode.
      if (!await cached.exists() || await cached.length() == 0) {
        final bytes = await ref
            .read(apiClientProvider)
            .getBytes('${AppConfig.apiOrigin}${widget.note.url}');
        if (bytes.isEmpty) throw Exception('empty audio download');
        await cached.writeAsBytes(bytes, flush: true);
      }

      final player = AudioPlayer();
      // Keep the source ready after a clip finishes rather than releasing it, so
      // the bar resets cleanly and a replay starts instantly.
      await player.setReleaseMode(ReleaseMode.stop);
      player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });
      player.onPlayerStateChanged.listen((_) {
        if (mounted) setState(() {});
      });
      // Reset the waveform to the start when the clip ends, so it reads as ready
      // to play again.
      player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _position = Duration.zero);
      });

      await player.play(DeviceFileSource(cached.path));
      if (!mounted) {
        await player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _loading = false;
      });
    } catch (e) {
      // Drop the half-written cache so a retry re-downloads a clean copy, and say
      // what failed (the class) rather than leaving a dead button.
      try {
        final dir = await getTemporaryDirectory();
        final ext = _extForMime(widget.note.mimeType);
        final f = File('${dir.path}/vn_${widget.note.url.hashCode}.$ext');
        if (await f.exists()) await f.delete();
      } catch (_) {}
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not play (${e.runtimeType})')),
        );
      }
    }
  }

  static String _extForMime(String? mime) {
    switch (mime) {
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/wav':
        return 'wav';
      case 'audio/ogg':
        return 'ogg';
      case 'audio/webm':
        return 'webm';
      case 'audio/aac':
        return 'aac';
      default:
        return 'm4a';
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
    // Same hue as the play glyph, half strength — the unplayed part of the
    // waveform reads as the same control rather than as grey filler.
    final track = widget.onDark
        ? Colors.white.withValues(alpha: 0.45)
        : AppColors.primary.withValues(alpha: 0.42);

    final playing = _player?.state == PlayerState.playing;
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
            SizedBox(
              width: 132,
              child: _Waveform(progress: progress, colour: fg, track: track),
            ),
          ],
        ),
        if (total != null) ...[
          const SizedBox(height: 5),
          Padding(
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

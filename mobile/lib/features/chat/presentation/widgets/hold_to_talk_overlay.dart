import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/gen/app_localizations.dart';
import 'voice_input_sheet.dart' show VoiceHoldController;
import 'voice_recognizer.dart';

/// WhatsApp-style hold-to-talk UI, rendered in the [Overlay] so it can float
/// the lock directly above the mic button and lay the recording bar over the
/// composer — neither of which a bottom sheet can do.
///
/// It never intercepts the press: while the finger is down it is wrapped in
/// [IgnorePointer], so the composer's long-press keeps driving cancel and lock.
/// Once locked (finger lifted) it becomes interactive for its Send/Cancel
/// controls.
class HoldToTalkView extends StatefulWidget {
  const HoldToTalkView({
    super.key,
    required this.recognizer,
    required this.hold,
    required this.micRect,
    required this.onLockedSend,
    required this.onLockedCancel,
  });

  final VoiceRecognizer recognizer;
  final VoiceHoldController hold;

  /// The mic button's rect in global (screen) coordinates.
  final Rect micRect;

  final VoidCallback onLockedSend;
  final VoidCallback onLockedCancel;

  @override
  State<HoldToTalkView> createState() => _HoldToTalkViewState();
}

class _HoldToTalkViewState extends State<HoldToTalkView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _mmss(Duration d) {
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final mic = widget.micRect;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.recognizer, widget.hold]),
      builder: (context, _) {
        final locked = widget.hold.locked;
        return IgnorePointer(
          // Interactive only once locked, so the composer keeps the gesture
          // while the finger is down.
          ignoring: !locked,
          child: Stack(
            children: [
              _recordingBar(context, mic, locked),
              _lockBubble(context, mic, locked),
              if (locked) _sendButton(context, mic),
            ],
          ),
        );
      },
    );
  }

  // The pill that lies over the composer: red dot, timer, waveform, hint.
  Widget _recordingBar(BuildContext context, Rect mic, bool locked) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final r = widget.recognizer;
    final armed = widget.hold.cancelArmed;

    return Positioned(
      left: 12,
      top: mic.top,
      height: mic.height,
      // Stop short of the mic (locked mode turns the mic into Send).
      width: (mic.left - 12 - 10).clamp(0.0, double.infinity),
      child: Material(
        color: scheme.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              // Locked: a tappable trash to discard. Held: a pulsing red dot.
              if (locked)
                _iconButton(Icons.delete_outline_rounded, AppColors.danger, widget.onLockedCancel)
              else
                FadeTransition(
                  opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                  ),
                ),
              const SizedBox(width: 12),
              Text(
                _mmss(r.elapsed),
                style: TextStyle(
                  fontSize: 15,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              // Everything past the timer is flexible, so a narrow composer or a
              // long localized hint shrinks rather than overflowing.
              Expanded(
                child: armed
                    ? Row(
                        children: [
                          const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.danger),
                          Flexible(
                            child: Text(
                              l10n.voiceReleaseToCancel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: _Waveform(levels: r.levels, color: AppColors.primary)),
                          if (!locked) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_left_rounded, size: 18, color: scheme.onSurfaceVariant),
                            Flexible(
                              child: Text(
                                l10n.voiceSlideToCancel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // The lock capsule floating above the mic. Fills toward the accent and snaps
  // closed as the finger rises.
  Widget _lockBubble(BuildContext context, Rect mic, bool locked) {
    final scheme = Theme.of(context).colorScheme;
    final p = widget.hold.lockProgress;
    final engaged = locked || p > 0.55;
    const size = 52.0;

    return Positioned(
      left: mic.center.dx - size / 2,
      // Sits above the mic; nudges up slightly as it engages.
      top: mic.top - 74 - (locked ? 6 : 0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size + 10,
        decoration: BoxDecoration(
          color: locked ? AppColors.primary : scheme.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: engaged ? AppColors.primary : scheme.outlineVariant,
            width: engaged ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              locked || engaged ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 22,
              color: locked ? Colors.white : (engaged ? AppColors.primary : scheme.onSurfaceVariant),
            ),
            if (!locked) ...[
              const SizedBox(height: 2),
              // Chevron fades as the lock engages.
              Opacity(
                opacity: (1 - p).clamp(0.0, 1.0),
                child: Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Locked mode: the mic position becomes a Send button.
  Widget _sendButton(BuildContext context, Rect mic) {
    return Positioned(
      left: mic.left,
      top: mic.top,
      width: mic.width,
      height: mic.height,
      child: Material(
        color: AppColors.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onLockedSend,
          child: const Center(child: Icon(Icons.send_rounded, color: Colors.white, size: 24)),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, size: 22, color: color)),
    );
  }
}

/// Live level meter drawn from the recogniser's rolling history.
class _Waveform extends StatelessWidget {
  const _Waveform({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // The bar row is wider than its slot in a narrow composer. Let it lay out
    // at its natural width off the right edge and clip, so the most recent bars
    // are always visible and it never overflows its parent.
    return SizedBox(
      height: 26,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.centerRight,
          maxWidth: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < levels.length; i++) ...[
                Container(
                  width: 3,
                  height: (4 + levels[i] * 22).clamp(4.0, 26.0),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.55 + 0.45 * levels[i]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (i != levels.length - 1) const SizedBox(width: 2),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

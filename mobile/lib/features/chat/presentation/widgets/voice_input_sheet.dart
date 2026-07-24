import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Locales offered to the recogniser. The engine needs an explicit locale —
/// left to guess, Bengali and Hindi speech comes back as Latin gibberish.
const Map<String, ({String localeId, String label})> kVoiceLocales = {
  'en': (localeId: 'en_IN', label: 'English'),
  'bn': (localeId: 'bn_IN', label: 'বাংলা'),
  'hi': (localeId: 'hi_IN', label: 'हिन्दी'),
};

enum _SheetState { listening, noSpeech, denied, unavailable }

/// Carries the press-and-hold gesture's live state from the composer (where the
/// finger is) to the sheet (which owns the recogniser), without either reaching
/// into the other's internals.
///
/// Terminal states are `released`, `cancelled`. `locked` is a mode, not a
/// terminal state: once locked, lifting the finger no longer ends the session —
/// the sheet's own Send/Cancel buttons do.
class VoiceHoldController extends ChangeNotifier {
  bool _released = false;
  bool _cancelled = false;
  bool _locked = false;

  /// True while the finger is far enough left that lifting will discard — used
  /// to turn the "slide to cancel" hint red before it commits.
  bool _cancelArmed = false;

  /// How far the finger has travelled toward the lock, 0..1. Drives the lock
  /// icon rising to meet the thumb, so the gesture has continuous feedback
  /// rather than snapping only at the threshold.
  double _lockProgress = 0;

  bool get released => _released;
  bool get cancelled => _cancelled;
  bool get locked => _locked;
  bool get cancelArmed => _cancelArmed;
  double get lockProgress => _lockProgress;

  /// Fed continuously from the finger position while held. Locks itself when
  /// progress reaches 1.
  void update({required double lockProgress, required bool cancelArmed}) {
    if (_released || _cancelled || _locked) return;
    var changed = false;
    if ((lockProgress - _lockProgress).abs() > 0.01) {
      _lockProgress = lockProgress;
      changed = true;
    }
    if (_cancelArmed != cancelArmed) {
      _cancelArmed = cancelArmed;
      changed = true;
    }
    if (lockProgress >= 1.0) {
      _locked = true;
      _cancelArmed = false;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Finger lifted. Ignored once locked — a lift after locking is expected.
  void release() {
    if (_locked || _released || _cancelled) return;
    _released = true;
    notifyListeners();
  }

  /// Discard. Works even when locked, so the sheet's Cancel button routes here.
  void cancel() {
    if (_released || _cancelled) return;
    _cancelled = true;
    notifyListeners();
  }

  /// Locked-mode Send: end and keep the transcript.
  void finishLocked() {
    if (_released || _cancelled) return;
    _released = true;
    notifyListeners();
  }
}

/// Bottom sheet that transcribes speech on-device and returns the text.
///
/// Returns the transcript via `Navigator.pop`, or null if cancelled. The
/// caller puts it in the composer for the patient to read — it is deliberately
/// **never** sent automatically. Speech recognition mishears numbers, and in
/// this app a number is a blood sugar reading: "forty" heard as "four hundred"
/// would raise an emergency that should not have fired, and the reverse would
/// miss one.
class VoiceInputSheet extends StatefulWidget {
  const VoiceInputSheet({
    super.key,
    required this.languageCode,
    this.holdToTalk = false,
    this.hold,
  });

  final String languageCode;

  /// Present only for press-and-hold sessions.
  final VoiceHoldController? hold;

  /// Opened by a press-and-hold on the mic rather than a tap. The sheet then
  /// ends on release instead of waiting for the Done button, which is the
  /// WhatsApp gesture applied to transcription.
  final bool holdToTalk;

  static Future<String?> show(
    BuildContext context, {
    required String languageCode,
    bool holdToTalk = false,
    VoiceHoldController? hold,
  }) {
    // Drop the keyboard first. Otherwise the sheet opens while `viewInsets`
    // still reports the keyboard's height, and the content is briefly laid
    // out into a viewport several hundred pixels shorter than the screen.
    FocusManager.instance.primaryFocus?.unfocus();

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Never taller than 90% of the screen; the rest scrolls.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      // A hold gesture must not be dismissible by the drag that ends it.
      isDismissible: !holdToTalk,
      enableDrag: !holdToTalk,
      builder: (_) => VoiceInputSheet(
        languageCode: languageCode,
        holdToTalk: holdToTalk,
        hold: hold,
      ),
    );
  }

  @override
  State<VoiceInputSheet> createState() => _VoiceInputSheetState();
}

class _VoiceInputSheetState extends State<VoiceInputSheet> with TickerProviderStateMixin {
  final SpeechToText _speech = SpeechToText();

  late final AnimationController _rotate;
  late final AnimationController _drift;

  late String _selectedLanguage;
  _SheetState _state = _SheetState.listening;

  String _finalWords = '';
  String _partialWords = '';

  /// Smoothed microphone level, 0..1. Raw values jitter per frame; the orb
  /// should breathe rather than flicker.
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = kVoiceLocales.containsKey(widget.languageCode) ? widget.languageCode : 'en';
    _rotate = AnimationController(vsync: this, duration: const Duration(milliseconds: 4000));
    _drift = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
    _rotate.repeat();
    _drift.repeat(reverse: true);
    widget.hold?.addListener(_onHoldChanged);
    unawaited(_start());
  }

  void _onHoldChanged() {
    final hold = widget.hold;
    if (hold == null || !mounted) return;
    if (hold.cancelled) {
      unawaited(_cancel());
    } else if (hold.released) {
      // Give the recogniser a beat to deliver its final result — cutting it
      // off the instant the finger lifts loses the last word or two.
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) unawaited(_finish());
      });
    } else {
      // locked / cancelArmed changed — repaint the hint.
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.hold?.removeListener(_onHoldChanged);
    _rotate.dispose();
    _drift.dispose();
    unawaited(_speech.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    final available = await _speech.initialize(
      onError: (_) {
        if (mounted && _finalWords.isEmpty && _partialWords.isEmpty) {
          setState(() => _state = _SheetState.noSpeech);
        }
      },
      onStatus: (status) {
        if (status == 'notListening' && mounted && _state == _SheetState.listening) {
          if (_finalWords.isEmpty && _partialWords.isEmpty) {
            setState(() => _state = _SheetState.noSpeech);
          }
        }
      },
    );

    if (!mounted) return;
    if (!available) {
      // `hasPermission` is a Future — distinguishes "user said no" from
      // "this device has no recogniser", which need different messages.
      final granted = await _speech.hasPermission;
      if (!mounted) return;
      setState(() => _state = granted ? _SheetState.unavailable : _SheetState.denied);
      return;
    }

    await _listen();
  }

  Future<void> _listen() async {
    setState(() {
      _state = _SheetState.listening;
      _finalWords = '';
      _partialWords = '';
    });
    await HapticFeedback.lightImpact();

    await _speech.listen(
      listenOptions: SpeechListenOptions(
        // An explicit locale is essential — left to guess, the recogniser
        // returns Bengali and Hindi speech as Latin gibberish. en_IN also
        // trains the model on Indian-accented English, which matters here.
        localeId: kVoiceLocales[_selectedLanguage]!.localeId,
        partialResults: true,
        cancelOnError: false,
        // The cloud recogniser is markedly more accurate than the offline
        // one, especially for Bengali/Hindi and for numbers — which is the
        // one thing that must not be misheard here. Falls back to on-device
        // automatically when offline.
        onDevice: false,
        // Adds full stops and commas, so a long spoken sentence lands as
        // readable text the patient can scan before sending.
        autoPunctuation: true,
        listenMode: ListenMode.dictation,
        // Longer than the old 4s: patients pause to think mid-sentence, and a
        // short window cut them off and lost the second half.
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(minutes: 2),
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          if (result.finalResult) {
            _finalWords = result.recognizedWords;
            _partialWords = '';
          } else {
            _partialWords = result.recognizedWords;
          }
        });
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        // speech_to_text reports roughly -2..10 on Android. Normalise, then
        // ease toward the target so the orb follows the voice smoothly.
        final normalised = ((level + 2) / 12).clamp(0.0, 1.0);
        setState(() => _level = _level + (normalised - _level) * 0.35);
      },
    );
  }

  String get _transcript => _finalWords.isNotEmpty ? _finalWords : _partialWords;

  Future<void> _finish() async {
    await _speech.stop();
    if (!mounted) return;
    final text = _transcript.trim();
    Navigator.of(context).pop(text.isEmpty ? null : text);
  }

  Future<void> _cancel() async {
    await _speech.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: AppSpacing.lg,
      ),
      child: SafeArea(
        top: false,
        // Scrollable so the sheet can never overflow — small screens, 200%
        // text scale and the taller Bengali/Devanagari glyph stacks all push
        // this content past the available height otherwise.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(alignment: Alignment.centerRight, child: _languageChip(context)),
              const SizedBox(height: AppSpacing.lg),
              ..._bodyFor(_state, l10n, scheme, reduceMotion),
              const SizedBox(height: AppSpacing.lg),
              ..._footer(l10n, scheme),
            ],
          ),
        ),
      ),
    );
  }

  /// The bottom controls, which differ by how the sheet was opened.
  List<Widget> _footer(AppLocalizations l10n, ColorScheme scheme) {
    final hold = widget.hold;
    final holding = widget.holdToTalk && hold != null;

    // Locked hands-free: the finger is up, so real Send / Cancel buttons.
    if (holding && hold.locked) {
      return [
        _primaryButton(
          label: l10n.voiceDone,
          enabled: _transcript.trim().isNotEmpty,
          onPressed: () => unawaited(_finish()),
        ),
        const SizedBox(height: AppSpacing.xs),
        _cancelTextButton(l10n, scheme),
      ];
    }

    // Still held down: the finger cannot press a button, so show the slide
    // affordances instead of controls the patient cannot reach. The lock track
    // and cancel hint are driven live by the finger position.
    if (holding) {
      return [
        _LockTrack(progress: hold.lockProgress, accent: AppColors.primary),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chevron_left_rounded,
              size: 20,
              color: hold.cancelArmed ? AppColors.danger : scheme.onSurfaceVariant,
            ),
            Text(
              hold.cancelArmed ? l10n.voiceReleaseToCancel : l10n.voiceSlideToCancel,
              style: TextStyle(
                fontSize: 15,
                fontWeight: hold.cancelArmed ? FontWeight.w600 : FontWeight.w400,
                color: hold.cancelArmed ? AppColors.danger : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ];
    }

    // Tap-to-open mode: ordinary buttons.
    return [
      _primaryButton(
        label: _state == _SheetState.noSpeech ? l10n.voiceTapToSpeak : l10n.voiceDone,
        enabled: _state == _SheetState.listening && _transcript.trim().isNotEmpty,
        onPressed: _state == _SheetState.listening && _transcript.trim().isNotEmpty
            ? () => unawaited(_finish())
            : (_state == _SheetState.noSpeech ? () => unawaited(_listen()) : null),
      ),
      const SizedBox(height: AppSpacing.xs),
      _cancelTextButton(l10n, scheme),
    ];
  }

  Widget _primaryButton({required String label, required bool enabled, VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.minTapTarget + 8,
      child: ElevatedButton(
        onPressed: enabled || _state == _SheetState.noSpeech ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _cancelTextButton(AppLocalizations l10n, ColorScheme scheme) {
    return TextButton(
      onPressed: () => unawaited(_cancel()),
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(AppSpacing.minTapTarget),
        foregroundColor: scheme.onSurfaceVariant,
      ),
      child: Text(l10n.voiceCancel, style: const TextStyle(fontSize: 16)),
    );
  }

  List<Widget> _bodyFor(
    _SheetState state,
    AppLocalizations l10n,
    ColorScheme scheme,
    bool reduceMotion,
  ) {
    switch (state) {
      case _SheetState.denied:
      case _SheetState.unavailable:
        return [
          Icon(Icons.mic_off_rounded, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: AppSpacing.md),
          Text(
            state == _SheetState.denied ? l10n.voicePermissionTitle : l10n.voiceUnavailable,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          if (state == _SheetState.denied) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.voicePermissionBody,
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ];

      case _SheetState.noSpeech:
        return [
          _VoiceOrb(
            rotate: _rotate,
            drift: _drift,
            level: 0,
            dimmed: true,
            reduceMotion: reduceMotion,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.voiceNoSpeech,
            style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ];

      case _SheetState.listening:
        return [
          Semantics(
            label: l10n.voiceListening,
            liveRegion: true,
            child: _VoiceOrb(
              rotate: _rotate,
              drift: _drift,
              level: _level,
              dimmed: false,
              reduceMotion: reduceMotion,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _AmplitudeBars(level: _level, reduceMotion: reduceMotion),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.voiceListening,
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Confirmed words render solid; the tail still being recognised is
          // greyed, so the patient can see what is settled and what is not.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 20, height: 1.4, color: scheme.onSurface),
                children: [
                  TextSpan(text: _finalWords),
                  if (_finalWords.isNotEmpty && _partialWords.isNotEmpty) const TextSpan(text: ' '),
                  TextSpan(
                    text: _partialWords,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (_transcript.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.voiceReviewBeforeSending,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ];
    }
  }

  Widget _languageChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      initialValue: _selectedLanguage,
      onSelected: (code) async {
        setState(() => _selectedLanguage = code);
        await _speech.stop();
        await _listen();
      },
      itemBuilder: (_) => kVoiceLocales.entries
          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value.label)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kVoiceLocales[_selectedLanguage]!.label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

/// The listening orb: a white disc ringed in teal, wrapped in a rotating
/// gradient halo that scales with the speaker's voice.
/// WhatsApp-style lock affordance: a vertical track with a lock icon at the
/// top and a thumb that rises to meet it as the finger slides up. When they
/// meet (progress 1.0) the session locks and the sheet swaps to Send/Cancel.
class _LockTrack extends StatelessWidget {
  const _LockTrack({required this.progress, required this.accent});

  /// 0 at rest, 1 when locked.
  final double progress;
  final Color accent;

  static const double _height = 96;
  static const double _thumb = 40;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // As the finger rises the lock "engages": the icon warms from grey to the
    // accent and swaps from open to closed near the top.
    final engaged = progress > 0.55;
    final lockColor = Color.lerp(scheme.onSurfaceVariant, accent, progress.clamp(0.0, 1.0))!;

    return SizedBox(
      width: 56,
      height: _height,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          // The track.
          Container(
            width: 44,
            height: _height,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: scheme.outlineVariant),
            ),
          ),
          // Lock icon pinned near the top.
          Positioned(
            top: 10,
            child: Icon(
              engaged ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 22,
              color: lockColor,
            ),
          ),
          // The thumb rises from the bottom toward the lock with progress.
          Positioned(
            bottom: 6 + progress * (_height - _thumb - 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: _thumb,
              height: _thumb,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14 + 0.5 * progress),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.keyboard_arrow_up_rounded, size: 24, color: accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceOrb extends StatelessWidget {
  const _VoiceOrb({
    required this.rotate,
    required this.drift,
    required this.level,
    required this.dimmed,
    required this.reduceMotion,
  });

  final AnimationController rotate;
  final AnimationController drift;
  final double level;
  final bool dimmed;
  final bool reduceMotion;

  static const double _size = 132;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: SizedBox(
        width: _size,
        height: _size,
        child: AnimatedBuilder(
          animation: Listenable.merge([rotate, drift]),
          builder: (context, child) {
            // 1.0 → 1.18 with voice. Reduced motion gets a gentle fixed pulse
            // instead of amplitude tracking.
            final scale = reduceMotion
                ? 1.0 + 0.06 * (0.5 + 0.5 * math.sin(drift.value * math.pi * 2))
                : 1.0 + 0.18 * level;
            return CustomPaint(
              painter: _OrbHaloPainter(
                rotation: reduceMotion ? 0 : rotate.value,
                drift: drift.value,
                scale: scale,
                dimmed: dimmed,
              ),
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: dimmed
                            ? scheme.outlineVariant
                            : AppColors.primary.withValues(alpha: 0.9),
                        width: 2.5,
                      ),
                    ),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 36,
                      color: dimmed ? scheme.onSurfaceVariant : AppColors.primary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Rotating gradient glow behind the orb.
class _OrbHaloPainter extends CustomPainter {
  const _OrbHaloPainter({
    required this.rotation,
    required this.drift,
    required this.scale,
    required this.dimmed,
  });

  final double rotation;
  final double drift;
  final double scale;
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (size.width / 2) * scale;

    if (dimmed) {
      canvas.drawCircle(
        centre,
        radius * 0.78,
        Paint()
          ..color = const Color(0xFF94A3B8).withValues(alpha: 0.14)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
      return;
    }

    // Soft outer glow.
    canvas.drawCircle(
      centre,
      radius * 0.86,
      Paint()
        ..color = AppColors.primaryDark.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // Rotating three-stop sweep, the Gemini-style moving light.
    final rect = Rect.fromCircle(center: centre, radius: radius * 0.80);
    canvas.drawCircle(
      centre,
      radius * 0.80,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(rotation * math.pi * 2),
          colors: const [
            AppColors.primary,
            AppColors.primaryDark,
            Color(0xFF5EEAD4),
            AppColors.primary,
          ],
          stops: const [0.0, 0.35, 0.68, 1.0],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  @override
  bool shouldRepaint(_OrbHaloPainter old) =>
      old.rotation != rotation ||
      old.drift != drift ||
      old.scale != scale ||
      old.dimmed != dimmed;
}

/// Small level meter under the orb — a secondary, unambiguous read for users
/// who find the orb decorative rather than informative.
class _AmplitudeBars extends StatelessWidget {
  const _AmplitudeBars({required this.level, required this.reduceMotion});

  final double level;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    // Each bar reacts slightly differently so the group looks like audio
    // rather than a single value repeated four times.
    const weights = [0.55, 1.0, 0.75, 0.4];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < weights.length; i++) ...[
          AnimatedContainer(
            duration: Duration(milliseconds: reduceMotion ? 0 : 60),
            curve: Curves.easeOut,
            width: 5,
            height: reduceMotion ? 16 : 8 + (32 * level * weights[i]),
            decoration: BoxDecoration(
              color: i.isEven ? AppColors.primaryDark : AppColors.primary,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i != weights.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

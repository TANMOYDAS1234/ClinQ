import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// Shown while awaiting `POST /chat/message`.
///
/// The light travels **around the border** of the bubble — it is painted as a
/// stroke on the rounded-rectangle outline, never as a bar or spinner inside
/// the bubble. Replies take 3–8 seconds in practice, long enough that a static
/// indicator reads as a hung app.
///
/// Never used for emergency or urgent replies: those must appear instantly at
/// full contrast, not be animated into view.
class GeneratingBubble extends StatefulWidget {
  const GeneratingBubble({super.key});

  @override
  State<GeneratingBubble> createState() => _GeneratingBubbleState();
}

class _GeneratingBubbleState extends State<GeneratingBubble> with TickerProviderStateMixin {
  late final AnimationController _sweep;
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    // Linear only. Any easing makes a continuous rotation look like it is
    // stuttering once per revolution.
    _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _shimmer = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Honour the OS reduce-motion setting: vestibular sensitivity is common in
    // this app's 45+ patient group.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _sweep.stop();
      _shimmer.stop();
    } else {
      if (!_sweep.isAnimating) _sweep.repeat();
      if (!_shimmer.isAnimating) _shimmer.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final width = MediaQuery.of(context).size.width * 0.62;

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: l10n.chatAnalyzing,
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, child) => CustomPaint(
                  painter: _BorderSweepPainter(
                    progress: _sweep.value,
                    radius: 20,
                    // A static full outline when motion is reduced — the
                    // bubble still reads as "pending", just without movement.
                    stationary: reduceMotion,
                    trackColor: scheme.outlineVariant,
                  ),
                  child: child,
                ),
                // Passed as AnimatedBuilder's `child` so the bubble subtree is
                // built once, not rebuilt on every frame of the sweep.
                child: Container(
                  width: width,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ShimmerLine(controller: _shimmer, widthFactor: 0.92, delay: 0),
                      const SizedBox(height: 10),
                      _ShimmerLine(controller: _shimmer, widthFactor: 0.74, delay: 0.22),
                      const SizedBox(height: 10),
                      _ShimmerLine(controller: _shimmer, widthFactor: 0.42, delay: 0.44),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.chatAnalyzing,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a travelling arc of light along the rounded-rectangle **outline**.
///
/// The gradient is a [SweepGradient] whose stops are rotated by [progress].
/// Because it is applied to a `PaintingStyle.stroke` on the bubble's own
/// rounded-rect path, the highlight follows the border — corners included —
/// rather than sitting anywhere inside the bubble.
class _BorderSweepPainter extends CustomPainter {
  const _BorderSweepPainter({
    required this.progress,
    required this.radius,
    required this.stationary,
    required this.trackColor,
  });

  final double progress;
  final double radius;
  final bool stationary;
  final Color trackColor;

  /// Fraction of the perimeter the visible highlight covers.
  static const double _arc = 0.35;
  static const double _strokeWidth = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(_strokeWidth / 2),
      Radius.circular(radius),
    );

    // Base outline, always present, so the bubble has a defined edge even at
    // the point in the cycle where the highlight is on the far side.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..color = trackColor,
    );

    if (stationary) return;

    final start = progress;
    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      transform: GradientRotation(start * math.pi * 2),
      colors: const [
        Color(0x0014B8A6),
        AppColors.primaryDark,
        Color(0xFF5EEAD4),
        Color(0x005EEAD4),
        Color(0x005EEAD4),
      ],
      stops: const [0.0, _arc * 0.45, _arc * 0.75, _arc, 1.0],
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BorderSweepPainter old) =>
      old.progress != progress || old.stationary != stationary || old.trackColor != trackColor;
}

/// One placeholder text line with a left-to-right shimmer highlight.
class _ShimmerLine extends StatelessWidget {
  const _ShimmerLine({required this.controller, required this.widthFactor, required this.delay});

  final AnimationController controller;
  final double widthFactor;

  /// Offsets this line's shimmer so the three do not move in lockstep.
  final double delay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.onSurface.withValues(alpha: 0.08);
    final highlight = scheme.onSurface.withValues(alpha: 0.16);

    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = (controller.value + delay) % 1.0;
          return Container(
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: LinearGradient(
                begin: Alignment(-1 + t * 3, 0),
                end: Alignment(-0.4 + t * 3, 0),
                colors: [base, highlight, base],
              ),
            ),
          );
        },
      ),
    );
  }
}

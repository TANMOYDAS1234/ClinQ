import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A rotating multi-colour sweep-gradient border, like Gemini's glowing input.
///
/// The animation only runs while [active] (focused or listening) — when idle it
/// paints a plain one-line outline and the controller is stopped, so it costs
/// nothing at rest. While [listening] it is thicker, spins faster and glows at
/// full strength.
class AnimatedGradientBorder extends StatefulWidget {
  const AnimatedGradientBorder({
    super.key,
    required this.child,
    required this.active,
    this.listening = false,
    this.radius = 26,
  });

  final Widget child;

  /// Focused or listening — turns the gradient on.
  final bool active;

  /// Listening — thicker, faster, brighter.
  final bool listening;

  final double radius;

  /// Seamless loop: the first and last colour match so the sweep has no seam.
  static const List<Color> colors = [
    Color(0xFF0F766E), // teal
    Color(0xFF06B6D4), // cyan
    Color(0xFF4F46E5), // indigo
    Color(0xFF7C3AED), // violet
    Color(0xFF0F766E), // teal (loop)
  ];

  @override
  State<AnimatedGradientBorder> createState() => _AnimatedGradientBorderState();
}

class _AnimatedGradientBorderState extends State<AnimatedGradientBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  static const _focusedTurn = Duration(milliseconds: 3200);
  static const _listeningTurn = Duration(milliseconds: 1600);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _turn);
  }

  Duration get _turn => widget.listening ? _listeningTurn : _focusedTurn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS reduce-motion setting: no spinning gradient, no idle CPU.
    // This also keeps widget tests deterministic — an ever-repeating animation
    // would otherwise hang pumpAndSettle.
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncAnimation();
  }

  void _syncAnimation() {
    _controller.duration = _turn;
    if (widget.active && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didUpdateWidget(AnimatedGradientBorder old) {
    super.didUpdateWidget(old);
    if (widget.listening != old.listening || widget.active != old.active) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Idle, or reduced motion: a plain outline, no animation.
    if (!widget.active || reduceMotion) {
      return RepaintBoundary(
        child: CustomPaint(
          painter: _BorderPainter(
            progress: 0,
            radius: widget.radius,
            listening: false,
            idle: true,
            idleColor: scheme.outlineVariant,
          ),
          child: widget.child,
        ),
      );
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _BorderPainter(
            progress: _controller.value,
            radius: widget.radius,
            listening: widget.listening,
            idle: false,
            idleColor: scheme.outlineVariant,
          ),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class _BorderPainter extends CustomPainter {
  const _BorderPainter({
    required this.progress,
    required this.radius,
    required this.listening,
    required this.idle,
    required this.idleColor,
  });

  final double progress;
  final double radius;
  final bool listening;
  final bool idle;
  final Color idleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = listening ? 2.4 : 1.6;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(stroke / 2),
      Radius.circular(radius),
    );

    if (idle) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = idleColor,
      );
      return;
    }

    final gradient = SweepGradient(
      colors: AnimatedGradientBorder.colors,
      transform: GradientRotation(progress * 2 * math.pi),
    ).createShader(rect);

    // Soft outer glow behind the crisp border.
    //
    // MaskFilter.blur is expensive per frame — running it while the patient is
    // just typing caused visible input lag on mid-range phones. So the blurred
    // glow is used ONLY while listening (a deliberate, brief, hero moment).
    // While merely focused, a wider translucent stroke gives a hint of glow at
    // a fraction of the cost.
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke + (listening ? 7 : 3)
      ..shader = gradient;
    if (listening) {
      glow.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    } else {
      glow.color = Colors.white.withValues(alpha: 0.4);
    }
    canvas.drawRRect(rrect, glow);

    // The crisp border.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = gradient,
    );
  }

  @override
  bool shouldRepaint(_BorderPainter old) =>
      old.progress != progress ||
      old.listening != listening ||
      old.idle != idle ||
      old.idleColor != idleColor;
}

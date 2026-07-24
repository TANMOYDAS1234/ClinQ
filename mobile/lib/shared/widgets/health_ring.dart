import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Circular progress ring used for the dashboard's health score (0-100) and
/// the medication adherence percentage. Drawn with a [CustomPainter] rather
/// than a chart package so it stays lightweight and fully themeable.
class HealthRing extends StatelessWidget {
  const HealthRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 140,
    this.strokeWidth = 14,
    this.centerLabel,
    this.centerSubLabel,
    this.trackColor,
  });

  /// 0.0 - 100.0
  final double value;
  final Color color;
  final double size;
  final double strokeWidth;
  final String? centerLabel;
  final String? centerSubLabel;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              value: value.clamp(0, 100),
              color: color,
              strokeWidth: strokeWidth,
              trackColor: trackColor ?? scheme.surfaceContainerHighest,
            ),
          ),
          if (centerLabel != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  centerLabel!,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (centerSubLabel != null)
                  Text(centerSubLabel!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.strokeWidth,
    required this.trackColor,
  });

  final double value;
  final Color color;
  final double strokeWidth;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    final sweep = (value / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

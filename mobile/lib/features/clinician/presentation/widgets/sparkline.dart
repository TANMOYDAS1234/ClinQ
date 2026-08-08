import 'package:flutter/material.dart';

/// A tiny inline glucose trend line for a patient roster row — drawn with a
/// CustomPainter rather than a chart library so a list of 100+ rows stays cheap.
///
/// Shows the recent readings as a smooth line with a soft area fill, a faint
/// target band (70-180 mg/dL) for reference, and a dot on the latest point.
/// Renders nothing meaningful below two points — callers should fall back to a
/// "no readings" hint instead.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.width = 72,
    this.height = 30,
    this.targetLow = 70,
    this.targetHigh = 180,
    this.showBand = true,
  });

  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final double targetLow;
  final double targetHigh;

  /// The 70-180 target band is glucose-specific; turn it off (and let the line
  /// scale to its own data) when plotting anything else, e.g. a daily count.
  final bool showBand;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(width: width, height: height);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          color: color,
          band: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
          targetLow: targetLow,
          targetHigh: targetHigh,
          showBand: showBand,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.color,
    required this.band,
    required this.targetLow,
    required this.targetHigh,
    required this.showBand,
  });

  final List<double> values;
  final Color color;
  final Color band;
  final double targetLow;
  final double targetHigh;
  final bool showBand;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale the Y axis to the data. When the target band is shown, keep it in
    // frame too so the line's position relative to "in range" stays meaningful.
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (showBand) {
      lo = lo < targetLow ? lo : targetLow;
      hi = hi > targetHigh ? hi : targetHigh;
    }
    final span = (hi - lo).abs() < 1 ? 1.0 : hi - lo;

    double y(double v) => size.height - ((v - lo) / span) * size.height;
    double x(int i) => (i / (values.length - 1)) * size.width;

    // Target band.
    if (showBand) {
      final bandRect = Rect.fromLTRB(0, y(targetHigh), size.width, y(targetLow));
      canvas.drawRect(bandRect, Paint()..color = band);
    }

    // Build the line path.
    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }

    // Soft area fill under the line.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    // The line itself.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    // Latest point.
    final lastX = x(values.length - 1);
    final lastY = y(values.last);
    canvas.drawCircle(Offset(lastX, lastY), 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color || old.band != band;
}

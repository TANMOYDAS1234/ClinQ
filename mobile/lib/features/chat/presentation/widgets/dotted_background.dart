import 'package:flutter/material.dart';

/// Faint dot grid behind the conversation, as in the design.
///
/// Painted rather than tiled from an asset so it inherits the theme in both
/// light and dark mode, and costs nothing to ship.
class DottedBackground extends StatelessWidget {
  const DottedBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DotGridPainter(
        // Deliberately near-invisible: it should read as paper texture, never
        // compete with message text for attention.
        color: scheme.onSurface.withValues(alpha: 0.06),
      ),
      // Isolate the grid from the child's repaints. Without this the whole dot
      // grid repainted on every keyboard-animation frame as the layout
      // resized, which was a visible cause of the input/keyboard lag.
      child: RepaintBoundary(child: child),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.color});

  final Color color;

  static const double _spacing = 24;
  static const double _radius = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = _spacing / 2; y < size.height; y += _spacing) {
      for (double x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

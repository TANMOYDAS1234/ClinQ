import 'package:flutter/material.dart';

/// The subtle medical-doodle wallpaper behind a chat thread — the same on the
/// patient's Assistant screen and the doctor's patient thread, like a messaging
/// app's chat background.
///
/// Shown only in light mode: the artwork is near-white and would glare in a dark
/// thread, so dark mode keeps the normal surface. A faint scrim sits over the
/// pattern so message bubbles keep their contrast, and a missing asset falls
/// back to a plain surface so the chat can never break over a wallpaper.
class ChatBackground extends StatelessWidget {
  const ChatBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // RepaintBoundary isolates the thread's repaints from the static background,
    // so the wallpaper does not re-composite on every keyboard/scroll frame
    // (the same guard the old dot grid needed to keep typing smooth).
    if (Theme.of(context).brightness == Brightness.dark) {
      return ColoredBox(color: scheme.surface, child: RepaintBoundary(child: child));
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/chat_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: scheme.surface),
          ),
        ),
        // Only a whisper of a wash: message bubbles are opaque, so text never
        // sits on the pattern — the artwork just needs to stay gentle in the
        // gaps, not disappear.
        Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.12))),
        RepaintBoundary(child: child),
      ],
    );
  }
}

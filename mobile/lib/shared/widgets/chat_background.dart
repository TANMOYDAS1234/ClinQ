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
    // Tiled, not stretched — the doodles repeat small and dense like a
    // messaging-app wallpaper (scale shrinks each tile), and faded to ~30% over
    // the surface so the pattern reads as a faint watermark and the message
    // bubbles clearly stand out on top. A missing asset just shows the surface.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        image: const DecorationImage(
          image: AssetImage('assets/images/chat_bg.jpg'),
          repeat: ImageRepeat.repeat,
          scale: 3.0,
          opacity: 0.30,
          filterQuality: FilterQuality.medium,
        ),
      ),
      child: RepaintBoundary(child: child),
    );
  }
}

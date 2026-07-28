import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../providers/core_providers.dart';

/// Full-screen, pinch-to-zoom view of a protected photo (a profile picture).
/// Fetched with the bearer token and token-tagged url, matching [UserAvatar] so
/// a rotated token doesn't leave a cached failure. Tap anywhere to dismiss.
class FullscreenPhoto extends ConsumerWidget {
  const FullscreenPhoto({super.key, required this.avatarUrl});

  /// Relative `/api/v1/uploads/:id/raw` path.
  final String avatarUrl;

  /// Opens the viewer, or does nothing when there is no photo to show.
  static Future<void> show(BuildContext context, String? avatarUrl) {
    if (avatarUrl == null || avatarUrl.isEmpty) return Future.value();
    return showGeneralDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      barrierDismissible: true,
      barrierLabel: 'photo',
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => FullscreenPhoto(avatarUrl: avatarUrl),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final headers = ref.watch(imageAuthHeaderProvider).valueOrNull;
    final ready = headers != null && headers.isNotEmpty;
    final tokenTag = ready ? headers.values.first.hashCode.toRadixString(36) : '0';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Stack(
          children: [
            Center(
              child: !ready
                  ? const CircularProgressIndicator(color: Colors.white)
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Image.network(
                        '${AppConfig.apiOrigin}$avatarUrl?v=$tokenTag',
                        headers: headers,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) =>
                            progress == null ? child : const Center(child: CircularProgressIndicator(color: Colors.white)),
                        errorBuilder: (_, _, _) => const Icon(Icons.person_rounded, color: Colors.white54, size: 120),
                      ),
                    ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

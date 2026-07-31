import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/auth_controller.dart';

/// Auth header for the owner-only `/uploads/:id/raw` image endpoint.
///
/// Re-read whenever the signed-in user changes, and never cached across
/// sessions: a globally-cached header could hold an empty token captured before
/// login (leaving the sender's own photos broken while everyone else's loaded)
/// or a stale one after a token refresh.
final _imageAuthHeaderProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  ref.watch(authControllerProvider);
  final token = await ref.watch(secureStoreProvider).readAccessToken();
  return token == null ? {} : {'Authorization': 'Bearer $token'};
});

/// Renders the photos attached to a chat message as rounded thumbnails.
///
/// The raw image is owner-protected, so it is fetched with the bearer token via
/// [Image.network]'s headers rather than a plain URL.
class ChatAttachmentThumbs extends ConsumerWidget {
  const ChatAttachmentThumbs({super.key, required this.paths});

  /// Relative `/api/v1/uploads/:id/raw` paths.
  final List<String> paths;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (paths.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final headers = ref.watch(_imageAuthHeaderProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final path in paths)
            GestureDetector(
              onTap: headers == null ? null : () => _openFullscreen(context, path, headers),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                child: Container(
                  width: 150,
                  height: 150,
                  color: scheme.surfaceContainerHighest,
                  child: headers == null
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : Image.network(
                          '${AppConfig.apiOrigin}$path',
                          headers: headers,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) => progress == null
                              ? child
                              : const Center(
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Tap a thumbnail to view it full-screen and zoom — useful for reading a
  /// prescription photo back.
  void _openFullscreen(BuildContext context, String path, Map<String, String> headers) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network('${AppConfig.apiOrigin}$path', headers: headers),
            ),
          ),
        ),
      ),
    );
  }
}

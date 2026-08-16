import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../providers/core_providers.dart';

/// Bearer header for the owner-protected `/uploads/:id/raw` endpoint. Re-read
/// on every auth change so it is never a stale or empty token.
final imageAuthHeaderProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  ref.watch(authControllerProvider);
  final token = await ref.watch(secureStoreProvider).readAccessToken();
  return token == null ? {} : {'Authorization': 'Bearer $token'};
});

/// A rounded, auth-protected image loaded from a `/api/v1/uploads/:id/raw` path.
class AuthedImage extends ConsumerWidget {
  const AuthedImage({
    super.key,
    required this.path,
    this.width = 64,
    this.height = 64,
    this.radius = 12,
    this.fit = BoxFit.cover,
    this.onTap,
    this.background,
  });

  final String path;
  final double width;
  final double height;
  final double radius;
  final BoxFit fit;

  /// The plate behind the image. Defaults to a grey that reads as "photo
  /// loading"; pass a colour (or transparent) where the image is cut out and
  /// meant to sit directly on the surface — a signature on grey stops looking
  /// like ink on paper.
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final headers = ref.watch(imageAuthHeaderProvider).valueOrNull;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: width,
          height: height,
          color: background ?? scheme.surfaceContainerHighest,
          child: headers == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Image.network(
                  '${AppConfig.apiOrigin}$path',
                  headers: headers,
                  fit: fit,
                  errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
                ),
        ),
      ),
    );
  }
}

/// Opens an auth-protected image full-screen with pinch-to-zoom.
void openAuthedImageFullscreen(BuildContext context, String path, Map<String, String> headers) {
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

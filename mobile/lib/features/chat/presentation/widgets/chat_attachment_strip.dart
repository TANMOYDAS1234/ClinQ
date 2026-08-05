import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

/// One photo queued for sending. [assetId] is null until `POST /uploads`
/// returns, which is what the spinner overlay indicates.
class PendingAttachment {
  const PendingAttachment({required this.localPath, this.assetId, this.failed = false, this.documentName});

  final String localPath;
  final String? assetId;
  final bool failed;

  /// Non-null when this is a document (PDF/Office/text) rather than a photo — the
  /// strip then shows a named file chip instead of an image thumbnail.
  final String? documentName;

  bool get isUploading => assetId == null && !failed;
  bool get isDocument => documentName != null;

  PendingAttachment copyWith({String? assetId, bool? failed}) => PendingAttachment(
    localPath: localPath,
    assetId: assetId ?? this.assetId,
    failed: failed ?? this.failed,
    documentName: documentName,
  );
}

/// Horizontal strip of thumbnails above the composer.
class ChatAttachmentStrip extends StatelessWidget {
  const ChatAttachmentStrip({super.key, required this.attachments, required this.onRemove});

  final List<PendingAttachment> attachments;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
        itemCount: attachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final a = attachments[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                child: Container(
                  width: 72,
                  height: 72,
                  color: scheme.surfaceContainerHighest,
                  padding: a.isDocument ? const EdgeInsets.all(6) : EdgeInsets.zero,
                  child: a.isDocument
                      // A document shows a file chip, not a photo thumbnail.
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.insert_drive_file_rounded, color: AppColors.accentOn(context), size: 26),
                            const SizedBox(height: 4),
                            Text(
                              a.documentName!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 9.5, height: 1.1, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        )
                      : Image.file(
                          File(a.localPath),
                          fit: BoxFit.cover,
                          // A picked file can vanish (cache eviction, permission
                          // revoked); a broken image must not take down the composer.
                          errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              if (a.isUploading)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                    child: Container(
                      color: Colors.black54,
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              if (a.failed)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
                    child: Container(
                      color: AppColors.dangerOn(context).withValues(alpha: 0.75),
                      child: const Center(
                        child: Icon(Icons.error_outline_rounded, color: Colors.white, size: 26),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: -6,
                right: -6,
                child: Semantics(
                  button: true,
                  label: l10n.chatAttachRemove,
                  child: InkWell(
                    onTap: () => onRemove(index),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Icon(Icons.close_rounded, size: 16, color: scheme.onSurface),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

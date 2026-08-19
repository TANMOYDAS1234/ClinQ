import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/chat_message.dart';

/// A shared document, shown WhatsApp-style: a typed icon, the filename and a
/// size/type line. Tapping downloads it (owner-protected, so with the bearer
/// token via Dio — an in-browser open would 403) and hands it to the phone's
/// own viewer.
class ChatDocumentCard extends ConsumerStatefulWidget {
  const ChatDocumentCard({super.key, required this.doc, required this.onDark});

  final DocumentAttachment doc;

  /// True inside the sender's own (deep green) bubble, where text inverts.
  final bool onDark;

  @override
  ConsumerState<ChatDocumentCard> createState() => _ChatDocumentCardState();
}

class _ChatDocumentCardState extends ConsumerState<ChatDocumentCard> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      // Keep the real filename so the opener matches it to the right app.
      final safe = widget.doc.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final cached = File('${dir.path}/doc_${widget.doc.url.hashCode}_$safe');
      if (!await cached.exists() || await cached.length() == 0) {
        final bytes = await ref
            .read(apiClientProvider)
            .getBytes('${AppConfig.apiOrigin}${widget.doc.url}');
        if (bytes.isEmpty) throw Exception('empty document download');
        await cached.writeAsBytes(bytes, flush: true);
      }
      final res = await OpenFilex.open(cached.path);
      if (res.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app on this phone can open that file')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the document')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = widget.onDark ? Colors.white : scheme.onSurface;
    final sub = widget.onDark ? Colors.white70 : scheme.onSurfaceVariant;
    final tint = _tint(widget.doc.mimeType);

    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: widget.onDark ? Colors.white.withValues(alpha: 0.15) : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: widget.onDark
              ? null
              : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: tint),
                    )
                  : Icon(_icon(widget.doc.mimeType), color: tint, size: 23),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.doc.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg),
                  ),
                  const SizedBox(height: 0),
                  Text(_meta(widget.doc), style: TextStyle(fontSize: 12, color: sub)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(String? m) {
    m ??= '';
    if (m == 'application/pdf') return Icons.picture_as_pdf_rounded;
    if (m.contains('word')) return Icons.description_rounded;
    if (m.contains('sheet') || m.contains('excel') || m == 'text/csv') return Icons.table_chart_rounded;
    if (m.contains('presentation') || m.contains('powerpoint')) return Icons.slideshow_rounded;
    if (m.startsWith('text/')) return Icons.article_rounded;
    return Icons.insert_drive_file_rounded;
  }

  static Color _tint(String? m) {
    m ??= '';
    if (m == 'application/pdf') return AppColors.danger;
    if (m.contains('word')) return const Color(0xFF2563EB);
    if (m.contains('sheet') || m.contains('excel') || m == 'text/csv') return AppColors.success;
    if (m.contains('presentation') || m.contains('powerpoint')) return const Color(0xFFEA580C);
    return AppColors.primary;
  }

  String _meta(DocumentAttachment d) {
    final type = _typeLabel(d.mimeType);
    final size = _size(d.sizeBytes);
    return size == null ? type : '$type · $size';
  }

  static String _typeLabel(String? m) {
    if (m == null) return 'File';
    if (m == 'application/pdf') return 'PDF';
    if (m.contains('word')) return 'Word';
    if (m.contains('sheet') || m.contains('excel')) return 'Excel';
    if (m == 'text/csv') return 'CSV';
    if (m.contains('presentation') || m.contains('powerpoint')) return 'PowerPoint';
    if (m.startsWith('text/')) return 'Text';
    return 'File';
  }

  static String? _size(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

/// The pinned message, held at the top of a thread.
///
/// A pin is worth nothing if you have to find the message again to read it —
/// the point is that the important line stays in front of you while the
/// conversation moves on underneath. The care thread has always done this; this
/// is the same banner, extracted so the nutrition thread can show it too and
/// the two cannot drift apart.
///
/// With more than one message pinned, the count appears and tapping cycles
/// through them.
class PinnedBanner extends StatelessWidget {
  const PinnedBanner({
    super.key,
    required this.preview,
    required this.count,
    required this.onTap,
    required this.onUnpin,
    this.label = 'Pinned message',
    this.unpinTooltip = 'Unpin',
  });

  /// The pinned message as plain text.
  final String preview;

  /// How many are pinned. The number shows only when it is more than one.
  final int count;

  final VoidCallback? onTap;
  final VoidCallback onUnpin;
  final String label;
  final String unpinTooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);

    return Material(
      color: scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, 4, 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: accent, width: 3),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 16, color: accent),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                        if (count > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '$count',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: unpinTooltip,
                onPressed: onUnpin,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

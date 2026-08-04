import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/citation.dart';

/// Shown under an assistant reply "when `citations` is non-empty". When [onTap]
/// is given, each pill is tappable — tapping asks the assistant about that topic.
class CitationChips extends StatelessWidget {
  const CitationChips({super.key, required this.citations, this.onTap});

  final List<Citation> citations;
  final ValueChanged<Citation>? onTap;

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    // Outlined pills carrying the source name directly, per the design. The
    // "Sources" heading is dropped — the chips read as sources on sight, and
    // the extra line pushed the disclaimer further from the answer.
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: citations.map((c) {
          final pill = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(c.title, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.north_east_rounded, size: 14, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          );
          return Tooltip(
            message: c.source,
            child: onTap == null
                ? pill
                : Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onTap!(c),
                      child: pill,
                    ),
                  ),
          );
        }).toList(),
      ),
    );
  }
}

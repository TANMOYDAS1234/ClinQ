import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/citation.dart';

/// Shown under an assistant reply "when `citations` is non-empty".
class CitationChips extends StatelessWidget {
  const CitationChips({super.key, required this.citations});

  final List<Citation> citations;

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
          return Tooltip(
            message: c.source,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Text(
                c.title,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

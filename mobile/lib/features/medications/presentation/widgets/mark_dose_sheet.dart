import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';

class MarkDoseResult {
  const MarkDoseResult({required this.status, this.skipReason});
  final String status; // taken | skipped
  final String? skipReason;
}

Future<MarkDoseResult?> showMarkDoseSheet(BuildContext context, String medicationName) {
  return showModalBottomSheet<MarkDoseResult>(
    context: context,
    showDragHandle: true,
    builder: (context) => _MarkDoseSheet(medicationName: medicationName),
  );
}

class _MarkDoseSheet extends StatelessWidget {
  const _MarkDoseSheet({required this.medicationName});

  final String medicationName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(medicationName, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
              onPressed: () =>
                  Navigator.of(context).pop(const MarkDoseResult(status: 'taken')),
              icon: const Icon(Icons.check_rounded),
              label: Text(l10n.medsMarkTaken),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: () async {
                final reason = await _pickSkipReason(context);
                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pop(MarkDoseResult(status: 'skipped', skipReason: reason));
                }
              },
              icon: const Icon(Icons.close_rounded),
              label: Text(l10n.medsMarkSkipped),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickSkipReason(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.medsSkipReasonTitle),
        content: TextField(controller: controller, autofocus: true, maxLines: 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
  }
}

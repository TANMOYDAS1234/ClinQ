import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../data/medications_repository.dart';
import '../../domain/medication.dart';

/// Scan a paper prescription into medicines: take a photo or pick one from the
/// gallery, the server reads it, and the medicines it finds are added with their
/// reminder times set automatically.
///
/// Returns `true` if any medicine was added.
Future<bool?> showScanPrescriptionSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _ScanPrescriptionSheet(),
  );
}

enum _Phase { choose, scanning, result }

class _ScanPrescriptionSheet extends ConsumerStatefulWidget {
  const _ScanPrescriptionSheet();

  @override
  ConsumerState<_ScanPrescriptionSheet> createState() => _ScanPrescriptionSheetState();
}

class _ScanPrescriptionSheetState extends ConsumerState<_ScanPrescriptionSheet> {
  _Phase _phase = _Phase.choose;
  PrescriptionScanResult? _result;

  Future<void> _pick(ImageSource source) async {
    final XFile? file = await ImagePicker().pickImage(
      source: source,
      // A prescription is text-dense; keep enough resolution for the OCR to read
      // small handwriting, but not so large the upload drags.
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (file == null || !mounted) return;

    setState(() => _phase = _Phase.scanning);
    try {
      final res = await ref
          .read(medicationsRepositoryProvider)
          .scanPrescription(path: file.path, filename: file.name);
      if (!mounted) return;
      setState(() {
        _result = res;
        _phase = _Phase.result;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _phase = _Phase.choose);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: switch (_phase) {
        _Phase.choose => _chooser(),
        _Phase.scanning => _scanning(),
        _Phase.result => _resultView(),
      },
    );
  }

  Widget _chooser() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Scan prescription', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "Take a clear photo of Dr.'s prescription — we'll read the medicines and set your daily reminders automatically.",
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: _SourceButton(
                icon: Icons.photo_camera_outlined,
                label: 'Take photo',
                onTap: () => _pick(ImageSource.camera),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _SourceButton(
                icon: Icons.photo_library_outlined,
                label: 'From gallery',
                onTap: () => _pick(ImageSource.gallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Icon(Icons.lightbulb_outline, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Good light and a flat, in-focus photo help us read it accurately.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scanning() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 40, height: 44, child: CircularProgressIndicator(strokeWidth: 3)),
          SizedBox(height: AppSpacing.lg),
          Text('Reading your prescription…', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('This takes a few seconds', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _resultView() {
    final res = _result!;
    final scheme = Theme.of(context).colorScheme;

    if (!res.readable || res.created.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 40, color: AppColors.warningOn(context)),
          const SizedBox(height: AppSpacing.sm),
          Text("Couldn't read that photo", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            res.note ?? 'Make sure the whole prescription is in frame, in focus, and well lit — then try again.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () => setState(() => _phase = _Phase.choose),
              icon: const Icon(Icons.refresh),
              label: const Text('Try another photo'),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.successOn(context), size: 26),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Added ${res.created.length} medicine${res.created.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Reminders are set. Please check they match your prescription — tap a medicine on the list to edit or stop it.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final m in res.created) _MedRow(med: m),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Done'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            Icon(icon, size: 30, color: AppColors.accentOn(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _MedRow extends StatelessWidget {
  const _MedRow({required this.med});

  final Medication med;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final times = med.schedule.map((s) => s.time).where((t) => t.isNotEmpty).join(', ');
    final subtitleBits = <String>[
      if (med.dose.isNotEmpty) med.dose,
      if (med.strength.isNotEmpty) med.strength,
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        ),
        child: Row(
          children: [
            Icon(Icons.medication_outlined, color: AppColors.accentOn(context)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(med.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  if (subtitleBits.isNotEmpty)
                    Text(subtitleBits.join(' · '), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14)),
                ],
              ),
            ),
            if (times.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.alarm, size: 15, color: AppColors.accentOn(context)),
                  const SizedBox(width: 4),
                  Text(times, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

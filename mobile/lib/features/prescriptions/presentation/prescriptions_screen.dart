import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/prescriptions_repository.dart';
import '../domain/patient_prescription.dart';

/// The patient's own prescriptions: every one the doctor issued, newest first,
/// each opening to its full detail with the option to view, share or save the
/// PDF from the app.
class PrescriptionsScreen extends ConsumerWidget {
  const PrescriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(patientPrescriptionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Prescriptions')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(patientPrescriptionsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 140),
              Center(child: Text('Could not load your prescriptions', style: TextStyle(color: scheme.onSurfaceVariant))),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(patientPrescriptionsProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.description_outlined, size: 52, color: scheme.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text('No prescriptions yet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text('They appear here once your doctor writes one.',
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _PrescriptionCard(
                rx: list[i],
                onTap: () => _showDetail(context, list[i]),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, PatientPrescription rx) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PrescriptionDetailSheet(rx: rx),
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.rx, required this.onTap});

  final PatientPrescription rx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = rx.issuedOn != null ? DateFormat('d MMM yyyy').format(rx.issuedOn!) : '—';
    final dx = rx.diagnosis.isNotEmpty ? rx.diagnosis.join(', ') : 'Prescription';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: AppColors.accentSoftOn(context), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.description_rounded, size: 20, color: AppColors.accentOn(context)),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(date, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
                      ),
                      if (rx.items.isNotEmpty)
                        Text('${rx.items.length} medicine${rx.items.length == 1 ? '' : 's'}',
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(dx,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  if (rx.doctorName != null) ...[
                    const SizedBox(height: 2),
                    Text('by ${rx.doctorName}', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PrescriptionDetailSheet extends ConsumerStatefulWidget {
  const _PrescriptionDetailSheet({required this.rx});

  final PatientPrescription rx;

  @override
  ConsumerState<_PrescriptionDetailSheet> createState() => _PrescriptionDetailSheetState();
}

class _PrescriptionDetailSheetState extends ConsumerState<_PrescriptionDetailSheet> {
  bool _busy = false;

  /// Downloads the PDF to a temp file so it can be opened or shared. Reused by
  /// both actions rather than fetched twice.
  Future<String?> _fetchPdf() async {
    final bytes = await ref.read(prescriptionsRepositoryProvider).pdfBytes(widget.rx.pdfUrl);
    final dir = await getTemporaryDirectory();
    final safe = widget.rx.referenceNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/prescription_${safe.isEmpty ? widget.rx.id : safe}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _open() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final path = await _fetchPdf();
      if (path != null) await OpenFilex.open(path);
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not open the prescription.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final path = await _fetchPdf();
      if (path != null) {
        // The OS share sheet is also where the patient saves/downloads the file
        // ("Save to Files" / "Download") or sends it on WhatsApp, email, etc.
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path, mimeType: 'application/pdf')],
            subject: 'Prescription ${widget.rx.referenceNo}',
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not share the prescription.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rx = widget.rx;
    final date = rx.issuedOn != null ? DateFormat('d MMMM yyyy').format(rx.issuedOn!) : '—';

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl),
        children: [
          Text(date, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            [if (rx.doctorName != null) 'by ${rx.doctorName}', rx.referenceNo].where((s) => s.isNotEmpty).join('  ·  '),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),

          // The PDF actions up top, so viewing/sharing the official document is
          // one tap and never a scroll away.
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _open,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: _busy
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Icon(Icons.picture_as_pdf_rounded, size: 19),
                  label: const Text('Open PDF'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _share,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  icon: const Icon(Icons.ios_share_rounded, size: 19),
                  label: const Text('Share / Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          if (rx.complaint != null && rx.complaint!.trim().isNotEmpty)
            _Section(title: 'Complaint', child: Text(rx.complaint!, style: const TextStyle(fontSize: 14.5, height: 1.4))),
          if (rx.diagnosis.isNotEmpty)
            _Section(title: 'Diagnosis', child: Text(rx.diagnosis.join('\n'), style: const TextStyle(fontSize: 14.5, height: 1.45))),
          if (rx.items.isNotEmpty)
            _Section(
              title: 'Medicines',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in rx.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                          if (m.detail.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(m.detail, style: TextStyle(fontSize: 13.5, height: 1.35, color: scheme.onSurfaceVariant)),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (rx.labTestsAdvised.isNotEmpty)
            _Section(title: 'Tests advised', child: Text(rx.labTestsAdvised.join(', '), style: const TextStyle(fontSize: 14.5, height: 1.4))),
          if (rx.generalAdvice != null && rx.generalAdvice!.trim().isNotEmpty)
            _Section(title: 'Advice', child: Text(rx.generalAdvice!, style: const TextStyle(fontSize: 14.5, height: 1.45))),
          if (rx.followUpOn != null)
            _Section(
              title: 'Follow-up',
              child: Text(DateFormat('d MMMM yyyy').format(rx.followUpOn!),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

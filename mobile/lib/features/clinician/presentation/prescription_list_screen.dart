import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/core_providers.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';

/// The patient's prescriptions, latest first — each a dated card with a summary
/// (diagnosis, medicine count, tests, follow-up) and a Download button that
/// pulls the server-generated PDF and opens it in the phone's viewer.
class PrescriptionListScreen extends ConsumerWidget {
  const PrescriptionListScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(patientPrescriptionsProvider(patientId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescriptions'),
        bottom: patientName == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(patientName!, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                ),
              ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(patientPrescriptionsProvider(patientId)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Could not load prescriptions', style: TextStyle(color: scheme.onSurfaceVariant))),
            ],
          ),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.receipt_long_outlined, size: 52, color: scheme.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      'No prescriptions yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'A consultation will add one here',
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (_, i) => _PrescriptionCard(rx: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _PrescriptionCard extends ConsumerStatefulWidget {
  const _PrescriptionCard({required this.rx});

  final PrescriptionSummary rx;

  @override
  ConsumerState<_PrescriptionCard> createState() => _PrescriptionCardState();
}

class _PrescriptionCardState extends ConsumerState<_PrescriptionCard> {
  bool _busy = false;

  Future<void> _download() async {
    final url = widget.rx.pdfUrl;
    if (url == null || url.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final name = '${widget.rx.referenceNo ?? widget.rx.id}.pdf'.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final cached = File('${dir.path}/rx_${url.hashCode}_$name');
      // Immutable documents, so a cached copy is always current.
      if (!await cached.exists() || await cached.length() == 0) {
        final bytes = await ref.read(apiClientProvider).getBytes('${AppConfig.apiOrigin}$url');
        if (bytes.isEmpty) throw Exception('empty pdf download');
        await cached.writeAsBytes(bytes, flush: true);
      }
      final res = await OpenFilex.open(cached.path);
      if (res.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app on this phone can open a PDF')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download the prescription')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rx = widget.rx;
    final date = rx.issuedOn == null ? '—' : DateFormat('d MMM yyyy, h:mm a').format(rx.issuedOn!);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (rx.referenceNo != null) ...[
                      const SizedBox(height: 0),
                      Text(rx.referenceNo!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (rx.diagnosis.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _line(context, Icons.local_hospital_outlined, rx.diagnosis.join(', ')),
          ],
          const SizedBox(height: 4),
          _line(
            context,
            Icons.medication_outlined,
            '${rx.itemCount} ${rx.itemCount == 1 ? 'medicine' : 'medicines'}'
                '${rx.labTestsAdvised.isNotEmpty ? '  ·  ${rx.labTestsAdvised.length} test${rx.labTestsAdvised.length == 1 ? '' : 's'} advised' : ''}',
          ),
          if (rx.followUpOn != null) ...[
            const SizedBox(height: 4),
            _line(context, Icons.event_outlined, 'Follow-up ${DateFormat('d MMM yyyy').format(rx.followUpOn!)}'),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _busy || rx.pdfUrl == null ? null : _download,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded, size: 18),
              label: Text(_busy ? 'Preparing…' : 'Download PDF'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 14, height: 1.3, color: scheme.onSurface)),
        ),
      ],
    );
  }
}

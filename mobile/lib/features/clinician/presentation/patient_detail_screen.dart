import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/patient_summary.dart';
import 'clinician_providers.dart';
import 'widgets/clinician_visuals.dart';

/// A patient's full clinical picture for the clinician: risk, health score,
/// adherence, glucose control, HbA1c history, recent alerts and the same
/// context the AI assistant sees.
class PatientDetailScreen extends ConsumerWidget {
  const PatientDetailScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patientSummaryProvider(patientId));

    return Scaffold(
      appBar: AppBar(title: const Text('Patient')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load patient'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: () => ref.invalidate(patientSummaryProvider(patientId)), child: const Text('Retry')),
            ],
          ),
        ),
        data: (p) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(patientSummaryProvider(patientId)),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Header(summary: p),
              const SizedBox(height: AppSpacing.md),
              _MetricsGrid(summary: p),
              if (p.hba1cHistory.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('HbA1c history'),
                const SizedBox(height: AppSpacing.sm),
                _Hba1cList(points: p.hba1cHistory),
              ],
              if (p.alerts.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Recent alerts'),
                const SizedBox(height: AppSpacing.sm),
                for (final a in p.alerts.take(8))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _AlertMini(
                      title: a.title,
                      severity: a.severity,
                      status: a.status,
                      when: a.createdAt,
                    ),
                  ),
              ],
              if (p.aiContext != null && p.aiContext!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Assistant context'),
                const SizedBox(height: AppSpacing.sm),
                _AiContextCard(text: p.aiContext!),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary});
  final PatientSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = summary;
    final band = riskBandColor(p.riskBand ?? 'low');
    final initial = (p.name.isNotEmpty ? p.name[0] : '?').toUpperCase();
    final meta = [
      if (p.age != null) '${p.age} yrs',
      if (p.gender != null) _cap(p.gender!),
      if (p.diabetesType != null) _diabetesLabel(p.diabetesType!),
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: band.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: Center(child: Text(initial, style: TextStyle(fontWeight: FontWeight.w800, color: band, fontSize: 22))),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    if (meta.isNotEmpty) Text(meta, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              MiniPill(label: '${riskBandLabel(p.riskBand ?? 'low')} risk', color: band, filled: true),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: p.phone)),
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/clinician/messages/${p.id}', extra: p.name),
                  icon: const Icon(Icons.forum_rounded, size: 18),
                  label: const Text('Message'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  String _diabetesLabel(String t) => switch (t) {
    'type1' => 'Type 1',
    'type2' => 'Type 2',
    'gestational' => 'Gestational',
    'prediabetes' => 'Prediabetes',
    'none' => 'Non-diabetic',
    _ => t,
  };
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.summary});
  final PatientSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = summary;
    final tiles = <Widget>[
      _Metric(
        label: 'Health score',
        value: p.healthScore?.toString() ?? '—',
        color: healthBandColor(p.healthBand),
        icon: Icons.favorite_rounded,
      ),
      _Metric(
        label: 'Adherence',
        value: p.adherencePercent != null ? '${p.adherencePercent}%' : '—',
        color: AppColors.primary,
        icon: Icons.medication_rounded,
      ),
      _Metric(
        label: 'Avg glucose',
        value: p.glucoseAverage != null ? '${p.glucoseAverage}' : '—',
        unit: p.glucoseAverage != null ? 'mg/dL' : null,
        color: AppColors.warning,
        icon: Icons.bloodtype_rounded,
      ),
      _Metric(
        label: 'Time in range',
        value: p.timeInRangePercent != null ? '${p.timeInRangePercent}%' : '—',
        color: AppColors.success,
        icon: Icons.check_circle_rounded,
      ),
      _Metric(
        label: 'Est. HbA1c',
        value: p.estimatedHba1c != null ? p.estimatedHba1c!.toStringAsFixed(1) : '—',
        unit: p.estimatedHba1c != null ? '%' : null,
        color: const Color(0xFF7C3AED),
        icon: Icons.science_rounded,
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 2.1,
      children: tiles,
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color, required this.icon, this.unit});

  final String label;
  final String value;
  final String? unit;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Text(unit!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Hba1cList extends StatelessWidget {
  const _Hba1cList({required this.points});
  final List<Hba1cPoint> points;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < points.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ListTile(
              dense: true,
              leading: Icon(Icons.science_outlined, color: points[i].percentage >= 9 ? AppColors.danger : (points[i].percentage >= 7 ? AppColors.warning : AppColors.success)),
              title: Text('${points[i].percentage}%', style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: Text(points[i].testedOn != null ? DateFormat('MMM yyyy').format(points[i].testedOn!) : ''),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertMini extends StatelessWidget {
  const _AlertMini({required this.title, required this.severity, required this.status, this.when});
  final String title;
  final String severity;
  final String status;
  final DateTime? when;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = alertSeverityColor(severity);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (when != null) Text(DateFormat('d MMM, h:mm a').format(when!), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          MiniPill(label: status == 'open' ? severity.toUpperCase() : status.toUpperCase(), color: status == 'open' ? color : const Color(0xFF6B7280)),
        ],
      ),
    );
  }
}

class _AiContextCard extends StatelessWidget {
  const _AiContextCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.5, color: scheme.onSurface)),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800));
}

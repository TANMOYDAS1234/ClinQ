import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/auto_refresh.dart';
import '../data/clinician_repository.dart';
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/clinician/patients/$patientId/prescribe', extra: async.valueOrNull?.name),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.edit_document),
        label: const Text('Prescribe'),
      ),
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
        data: (p) => AutoRefresh(
          onTick: (r) => r.invalidate(patientSummaryProvider(patientId)),
          child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(patientSummaryProvider(patientId)),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _Header(summary: p),
              const SizedBox(height: AppSpacing.md),
              _MetricsGrid(summary: p),
              const SizedBox(height: AppSpacing.lg),
              _DieticianSection(summary: p, patientId: patientId),
              if (p.hba1cHistory.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('HbA1c history'),
                const SizedBox(height: AppSpacing.sm),
                _Hba1cList(points: p.hba1cHistory),
              ],
              if (p.labResults.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Test reports'),
                const SizedBox(height: AppSpacing.sm),
                for (final r in p.labResults.take(12))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _LabReportRow(report: r),
                  ),
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
                  onPressed: () => context.push('/clinician/patients/${p.id}/thread', extra: p.name),
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

/// Shows the patient's assigned dietician + food-log review cadence, and lets
/// the doctor assign, change, or clear it.
class _DieticianSection extends ConsumerWidget {
  const _DieticianSection({required this.summary, required this.patientId});

  final PatientSummary summary;
  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final name = summary.assignedDieticianName;
    final cadence = summary.reviewIntervalDays;
    final assigned = name != null && name.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.restaurant_menu_rounded, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DIETICIAN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(assigned ? name : 'Not assigned', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                if (assigned && cadence != null)
                  Text('Reviews food log every $cadence day${cadence == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          TextButton(onPressed: () => _openAssign(context, ref), child: Text(assigned ? 'Change' : 'Assign')),
        ],
      ),
    );
  }

  Future<void> _openAssign(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(clinicianRepositoryProvider);

    List<({String id, String name})> options;
    try {
      options = await repo.dieticians();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not load dieticians')));
      return;
    }
    if (!context.mounted) return;

    String? selectedId = summary.assignedDieticianId;
    int cadence = summary.reviewIntervalDays ?? 3;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Assign dietician', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: AppSpacing.sm),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('No dieticians yet — add one below.',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ),
              for (final d in options)
                RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: d.id,
                  groupValue: selectedId,
                  onChanged: (v) => setSheet(() => selectedId = v),
                  title: Text(d.name),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final created = await _addDieticianForm(ctx, repo);
                    if (created != null) {
                      try {
                        options = await repo.dieticians();
                      } catch (_) {}
                      setSheet(() => selectedId = created.id);
                    }
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('Add a new dietician'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text('Review the food log every', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final (days, label) in const [(1, 'Daily'), (3, 'Every 3 days'), (7, 'Weekly')])
                    ChoiceChip(
                      label: Text(label),
                      selected: cadence == days,
                      onSelected: (_) => setSheet(() => cadence = days),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (summary.assignedDieticianId != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: () async {
                        try {
                          await repo.assignDietician(patientId, dieticianId: null, reviewIntervalDays: null);
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (_) {
                          if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Could not save')));
                        }
                      },
                      child: const Text('Unassign'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: selectedId == null
                        ? null
                        : () async {
                            try {
                              await repo.assignDietician(patientId, dieticianId: selectedId, reviewIntervalDays: cadence);
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (_) {
                              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Could not save')));
                            }
                          },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) {
      ref.invalidate(patientSummaryProvider(patientId));
      messenger.showSnackBar(const SnackBar(content: Text('Dietician updated')));
    }
  }

  /// A small inline form to create a dietician account. Returns the new
  /// dietician (id + name), or null if cancelled.
  Future<({String id, String name})?> _addDieticianForm(BuildContext ctx, ClinicianRepository repo) {
    final name = TextEditingController();
    final phone = TextEditingController();
    final password = TextEditingController();
    return showDialog<({String id, String name})?>(
      context: ctx,
      builder: (dctx) {
        bool saving = false;
        String? error;
        return StatefulBuilder(
          builder: (dctx, setD) => AlertDialog(
            title: const Text('Add dietician'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone (e.g. +9198…)')),
                TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Temporary password (8+ chars)')),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (name.text.trim().length < 2 || phone.text.trim().isEmpty || password.text.length < 8) {
                          setD(() => error = 'Enter a name, phone, and an 8+ character password.');
                          return;
                        }
                        setD(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final d = await repo.addDietician(name: name.text.trim(), phone: phone.text.trim(), password: password.text);
                          if (dctx.mounted) Navigator.pop(dctx, d);
                        } on ApiException catch (e) {
                          setD(() {
                            saving = false;
                            error = e.message;
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LabReportRow extends StatelessWidget {
  const _LabReportRow({required this.report});

  final LabReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AuthedImage(path: report.photoUrl!, width: 52, height: 52, radius: 10),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(report.testName, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
                    if (report.createdAt != null)
                      Text(DateFormat('d MMM').format(report.createdAt!), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
                if (report.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(report.note, style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
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

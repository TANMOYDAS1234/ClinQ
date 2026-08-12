import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../medications/domain/med_shorthand.dart';
import '../domain/lab_catalog.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../medications/domain/medication.dart';
import '../data/clinician_repository.dart';
import '../domain/patient_summary.dart';
import 'clinician_providers.dart';
import 'patient_detail_screen.dart' show PatientRecordSections;

/// The doctor's working screen for one patient: who they are at the top, and
/// everything the doctor might do about it underneath.
///
/// The prescribing form lives here rather than behind a second navigation step,
/// because writing the prescription IS the consultation — making the doctor
/// open another screen to do the main thing is a tap between them and the work.
/// The full clinical record sits one tap away in the overflow menu.
class PatientProfileScreen extends ConsumerStatefulWidget {
  const PatientProfileScreen({super.key, required this.patientId});

  final String patientId;

  @override
  ConsumerState<PatientProfileScreen> createState() => _PatientProfileScreenState();
}

class _PatientProfileScreenState extends ConsumerState<PatientProfileScreen> {
  final List<_MedDraft> _meds = [_MedDraft()];
  final _diagnosis = TextEditingController();
  final _advice = TextEditingController();
  final _labSearch = TextEditingController();

  final Set<String> _selectedTests = {};
  final List<String> _customTests = [];

  DateTime? _followUp;
  bool _saving = false;

  @override
  void dispose() {
    for (final m in _meds) {
      m.dispose();
    }
    _diagnosis.dispose();
    _advice.dispose();
    _labSearch.dispose();
    super.dispose();
  }

  void _addCustomTest() {
    final text = _labSearch.text.trim();
    if (text.isEmpty) return;
    setState(() {
      // If it's a known panel, order it by its canonical catalog name.
      final panel = labPanelFor(text);
      final name = panel?.name ?? text;
      if (panel == null && !_customTests.any((t) => t.toLowerCase() == text.toLowerCase())) {
        _customTests.add(text);
      }
      _selectedTests.add(name);
      _labSearch.clear();
    });
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _followUp = picked);
  }

  Future<void> _send() async {
    final items = _meds
        .where((m) => m.name.text.trim().isNotEmpty)
        .map(
          (m) => <String, dynamic>{
            'name': m.name.text.trim(),
            if (m.dosage.text.trim().isNotEmpty) 'strength': m.dosage.text.trim(),
            'frequency': m.frequency.apiFrequency,
            'relationToMeal': m.frequency.takesMealRelation ? m.relation.api : 'any',
            'route': m.route.api,
            if (int.tryParse(m.duration.text.trim()) != null)
              'durationDays': int.parse(m.duration.text.trim()),
          },
        )
        .toList();

    final messenger = ScaffoldMessenger.of(context);
    if (items.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add at least one medicine (a name is required).')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(clinicianRepositoryProvider).createPrescription(
        patientId: widget.patientId,
        items: items,
        // Each non-empty line is a diagnosis item — matches how the AI context
        // and the prescription PDF list them.
        diagnosis: _diagnosis.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        labTestsAdvised: _selectedTests.toList(),
        generalAdvice: _advice.text.trim().isEmpty ? null : _advice.text.trim(),
        followUpOn: _followUp,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Prescription sent — added to the patient’s tracker')),
      );
      // Clear rather than pop: the doctor stays with the patient they are
      // seeing, and the record behind this form has just changed.
      setState(() {
        for (final m in _meds) {
          m.dispose();
        }
        _meds
          ..clear()
          ..add(_MedDraft());
        _diagnosis.clear();
        _advice.clear();
        _selectedTests.clear();
        _followUp = null;
        _saving = false;
      });
      ref.invalidate(patientSummaryProvider(widget.patientId));
      // The list above this form has just gained what was written into it.
      ref.invalidate(patientMedicationsProvider(widget.patientId));
      // Today's consultation now shows in the record's history.
      ref.invalidate(patientPrescriptionsProvider(widget.patientId));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(patientSummaryProvider(widget.patientId));

    return Scaffold(
      // No overflow menu: the two secondary destinations sit at the foot of the
      // screen instead, after the primary action, where secondary actions
      // belong. Dropping them entirely would leave the clinical record — HbA1c,
      // reports, alerts, dietician — with no route to it at all.
      appBar: AppBar(title: const Text('Patient Profile')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load patient'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => ref.invalidate(patientSummaryProvider(widget.patientId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (p) => ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xl),
          children: [
            _ProfileHeader(patient: p),
            const SizedBox(height: AppSpacing.lg),

            // The read side of the record — health metrics, the trend graph,
            // HbA1c history, uploaded reports, alerts and the dietician
            // assignment — above the actions so the doctor sees the patient's
            // status before prescribing. (This whole block was orphaned by an
            // earlier refactor; the data was fetched but never shown.)
            PatientRecordSections(summary: p, patientId: widget.patientId),
            const SizedBox(height: AppSpacing.lg),

            const Text('Clinical Actions', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            _ActionCard(
              icon: Icons.assignment_outlined,
              title: 'Medication',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What the patient is already on, before the box for what to
                  // add. Prescribing without it is prescribing blind — a repeat
                  // or an interaction is invisible until the patient reports it.
                  _CurrentMedicines(patientId: widget.patientId),
                  for (var i = 0; i < _meds.length; i++)
                    _MedFields(
                      draft: _meds[i],
                      onChanged: () => setState(() {}),
                      onRemove: _meds.length > 1
                          ? () => setState(() => _meds.removeAt(i).dispose())
                          : null,
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: AppColors.primary,
                      ),
                      onPressed: () => setState(() => _meds.add(_MedDraft())),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                      label: const Text(
                        'Add another medication',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            _ActionCard(
              icon: Icons.biotech_outlined,
              title: 'Lab Tests',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Already ordered, and already come back. Without these the
                  // doctor re-ordered tests that were outstanding and could not
                  // see the report the patient had already uploaded.
                  _TestHistory(summary: p),
                  // An add control, not a search: what is typed here becomes a
                  // new chip. The leading + says so; a magnifier would promise
                  // a lookup that does not exist.
                  Row(
                    children: [
                      Expanded(
                        child: _PlainField(
                          controller: _labSearch,
                          hint: 'Add another test',
                          icon: Icons.add_rounded,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _addCustomTest(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      IconButton.filledTonal(
                        onPressed: _addCustomTest,
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // The diabetes lab catalog, grouped by category. The doctor
                  // orders at the PANEL level; each panel's sub-tests are shown
                  // beneath the selection so "what the report includes" is clear.
                  for (final entry in labCatalogByCategory().entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 6),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final panel in entry.value)
                          _TestChip(
                            label: panel.name,
                            selected: _selectedTests.contains(panel.name),
                            onTap: () => setState(() {
                              if (!_selectedTests.remove(panel.name)) _selectedTests.add(panel.name);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (_customTests.isNotEmpty)
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final test in _customTests)
                          _TestChip(
                            label: test,
                            selected: _selectedTests.contains(test),
                            onTap: () => setState(() {
                              if (!_selectedTests.remove(test)) _selectedTests.add(test);
                            }),
                          ),
                      ],
                    ),
                  // Sub-tests under each selected panel.
                  for (final t in _selectedTests)
                    if ((labPanelFor(t)?.analytes ?? const []).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.subdirectory_arrow_right_rounded,
                                size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '$t: ${labPanelFor(t)!.analytes.join(' · ')}',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.3,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            _ActionCard(
              icon: Icons.edit_note_rounded,
              title: 'Clinical Advice',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('Diagnosis'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _diagnosis,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Type 2 DM, Hypertension (one per line)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _FieldLabel('General advice'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _advice,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Diet, lifestyle and general instructions...',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            _ActionCard(
              icon: Icons.calendar_month_outlined,
              title: 'Follow-up',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _FieldLabel('Next Visit'),
                  const SizedBox(height: 6),
                  _DateField(date: _followUp, onTap: _pickFollowUp, onClear: () => setState(() => _followUp = null)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            SizedBox(
              height: AppSpacing.minTapTarget + 12,
              child: FilledButton.icon(
                onPressed: _saving ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 21),
                label: const Text(
                  'Send Prescription',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Header ---------------------------------------------------------------

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.patient});

  final PatientSummary patient;

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String? _diabetesLabel(String? t) => switch (t) {
    'type1' => 'Type 1 DM',
    'type2' => 'Type 2 DM',
    'gestational' => 'Gestational',
    'prediabetes' => 'Prediabetes',
    'none' => 'Non-diabetic',
    null => null,
    _ => t,
  };

  @override
  Widget build(BuildContext context) {
    final p = patient;
    final band = p.riskBand ?? 'low';
    final atRisk = band == 'high' || band == 'critical';
    // No patient ID here. The design showed one, but the only id available is a
    // truncation of the record id — not guaranteed unique, yet it reads like an
    // official number. The day someone quotes it on a lab form, a collision is
    // patient misidentification. A real clinic number would have to be stored,
    // sequential and unique; until it is, showing nothing is safer than showing
    // something that looks official and is not.
    final meta = [
      if (p.age != null) '${p.age} Yrs',
      if (p.gender != null) _cap(p.gender!),
      p.phone,
    ].where((s) => s.isNotEmpty).join('  •  ');
    final diabetes = _diabetesLabel(p.diabetesType);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoftOn(context),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              UserAvatar(name: p.name, avatarUrl: p.avatarUrl, accent: AppColors.accentOn(context), size: 62),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, height: 1.2),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.accentOn(context).withValues(alpha: 0.75),
                      ),
                    ),
                    if ((p.address ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.home_outlined,
                            size: 14,
                            color: AppColors.accentOn(context).withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              p.address!.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                color: AppColors.accentOn(context).withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 6,
                      children: [
                        _HeaderPill(
                          // The warning triangle appears only when the band
                          // earns it — a permanent icon stops being a warning.
                          icon: atRisk ? Icons.warning_amber_rounded : null,
                          label: '${_cap(band)} Risk',
                          fg: atRisk ? AppColors.danger : AppColors.primary,
                          bg: atRisk ? AppColors.dangerBgOn(context) : Colors.white,
                        ),
                        if (diabetes != null)
                          _HeaderPill(label: diabetes, fg: AppColors.primary, bg: Colors.white),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: p.phone)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.call_rounded, size: 19),
                  label: const Text('Call', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => context.push('/clinician/patients/${p.id}/thread', extra: p.name),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                  label: const Text(
                    'Message',
                    style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if ((p.chiefComplaint ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.assignment_outlined, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                            text: 'Complaint   ',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: p.chiefComplaint!.trim()),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13.5, height: 1.35, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.label, required this.fg, required this.bg, this.icon});

  final String label;
  final Color fg;
  final Color bg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

// ---- Action cards ---------------------------------------------------------

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.icon, required this.title, required this.child});

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 21, color: scheme.onSurface),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.7)),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// The patient's running medication list, with a way to stop any of them.
///
/// Stopping is a soft stop on the server: the medicine is marked inactive with
/// an end date rather than deleted, so the doses already logged against it — and
/// the adherence figure built from them — stay interpretable.
class _CurrentMedicines extends ConsumerWidget {
  const _CurrentMedicines({required this.patientId});

  final String patientId;

  Future<void> _stop(BuildContext context, WidgetRef ref, Medication med) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Stop ${med.name}?'),
        content: const Text(
          'The patient stops being reminded about it from now on. Doses already '
          'recorded are kept.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop it'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(clinicianRepositoryProvider).stopMedication(patientId, med.id);
      ref.invalidate(patientMedicationsProvider(patientId));
      messenger.showSnackBar(SnackBar(content: Text('${med.name} stopped')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(patientMedicationsProvider(patientId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.md),
        child: LinearProgressIndicator(minHeight: 2),
      ),
      // A failure here must not read as "no medicines" — that is the one
      // wrong answer a prescribing screen can give.
      error: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 17, color: AppColors.dangerOn(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Could not load current medicines.',
                style: TextStyle(fontSize: 13, color: AppColors.dangerOn(context)),
              ),
            ),
            TextButton(
              onPressed: () => ref.invalidate(patientMedicationsProvider(patientId)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (meds) {
        final active = meds.where((m) => m.isActive).toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'CURRENTLY ON',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${active.length}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.accentOn(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (active.isEmpty)
                Text(
                  'Nothing prescribed yet.',
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                )
              else
                for (final med in active)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [med.name, med.strength].where((s) => s.isNotEmpty).join(' '),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (med.dose.isNotEmpty) med.dose,
                                  med.doseSummary,
                                  if (med.schedule.isNotEmpty)
                                    med.schedule.map((s) => s.time).join(', '),
                                ].join(' · '),
                                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.dangerOn(context),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _stop(context, ref, med),
                          child: const Text(
                            'Stop',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: AppSpacing.sm),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
              const SizedBox(height: AppSpacing.md),
              Text(
                'ADD NEW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

/// What has already been ordered for this patient, and what has come back.
class _TestHistory extends StatelessWidget {
  const _TestHistory({required this.summary});

  final PatientSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final advised = summary.advisedTests;
    final reports = summary.labResults;
    if (advised.isEmpty && reports.isEmpty) return const SizedBox.shrink();

    // A test counts as back when a report carries its name. Matched loosely,
    // because the patient types the name when they upload against "Other".
    bool hasReport(String test) => reports.any(
      (r) => r.testName.trim().toLowerCase() == test.trim().toLowerCase(),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (advised.isNotEmpty) ...[
            _MicroHeading('ALREADY ORDERED', count: advised.length),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in advised)
                  Chip(
                    avatar: Icon(
                      hasReport(t) ? Icons.check_circle_rounded : Icons.hourglass_empty_rounded,
                      size: 16,
                      color: hasReport(t)
                          ? AppColors.successOn(context)
                          : AppColors.warningOn(context),
                    ),
                    label: Text(
                      t,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: scheme.surfaceContainerLow,
                    side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (reports.isNotEmpty) ...[
            _MicroHeading('REPORTS RECEIVED', count: reports.length),
            const SizedBox(height: AppSpacing.sm),
            for (final r in reports.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    // Only a picture gets a thumbnail; a PDF drawn through the
                    // image loader is the broken box the patient's screen had.
                    if (r.hasFile && r.isImage)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: AuthedImage(path: r.photoUrl!, width: 44, height: 44, radius: 8),
                      )
                    else
                      Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(right: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.description_outlined,
                          size: 21,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r.testName,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            r.createdAt == null
                                ? (r.originalName ?? '')
                                : DateFormat('d MMM yyyy').format(r.createdAt!),
                            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}

class _MicroHeading extends StatelessWidget {
  const _MicroHeading(this.text, {this.count});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.accentOn(context),
            ),
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
    );
  }
}

/// A plain text field. Deliberately no magnifier anywhere on this screen: there
/// is no lookup behind these fields, and a search icon over a field that only
/// accepts what you type is a promise the form cannot keep — the doctor types
/// three letters, waits for a dropdown, and nothing comes.
class _PlainField extends StatelessWidget {
  const _PlainField({
    required this.controller,
    required this.hint,
    this.icon,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      textCapitalization: TextCapitalization.words,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

// ---- Medication -----------------------------------------------------------

/// One medicine being written. The doctor picks in medical shorthand
/// (frequency + meal relation + route); the composed short form ("BDPC") and the
/// patient's plain phrase ("Twice a day, after food") both come from
/// [med_shorthand], so the two can never drift.
class _MedDraft {
  final name = TextEditingController();
  final dosage = TextEditingController();
  final duration = TextEditingController();
  DoseFrequency frequency = DoseFrequency.bd;
  MealRelation relation = MealRelation.after;
  MedRoute route = MedRoute.oral;

  String get shorthand => composeShorthand(frequency: frequency, relation: relation, route: route);
  String get plain => expandToPlain(frequency: frequency, relation: relation, route: route);

  void dispose() {
    name.dispose();
    dosage.dispose();
    duration.dispose();
  }
}

class _MedFields extends StatelessWidget {
  const _MedFields({required this.draft, required this.onChanged, required this.onRemove});

  final _MedDraft draft;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _FieldLabel('Medicine Name')),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _PlainField(controller: draft.name, hint: 'e.g. Metformin'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Dosage'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: draft.dosage,
                      decoration: const InputDecoration(hintText: 'e.g. 500mg', isDense: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel('Duration (days)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: draft.duration,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(hintText: 'e.g. 14', isDense: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const _FieldLabel('Frequency'),
              const Spacer(),
              // Live composed medical shorthand, e.g. "BDPC" / "TDS AC" / "HS".
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.accentSoftOn(context), borderRadius: BorderRadius.circular(7)),
                child: Text(draft.shorthand,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.accentOn(context))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final f in DoseFrequency.values)
                _ShChip(
                  label: f.code,
                  selected: draft.frequency == f,
                  onTap: () {
                    draft.frequency = f;
                    onChanged();
                  },
                ),
            ],
          ),
          if (draft.frequency.takesMealRelation) ...[
            const SizedBox(height: AppSpacing.sm),
            const _FieldLabel('Timing'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in MealRelation.values)
                  _ShChip(
                    label: _relLabel(r),
                    selected: draft.relation == r,
                    onTap: () {
                      draft.relation = r;
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const _FieldLabel('Route'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final rt in MedRoute.values)
                _ShChip(
                  label: rt.code,
                  selected: draft.route == rt,
                  onTap: () {
                    draft.route = rt;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Patient sees: ${draft.plain}',
              style: TextStyle(
                  fontSize: 12, fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

String _relLabel(MealRelation r) => switch (r) {
  MealRelation.anytime => 'Any',
  MealRelation.before => 'AC',
  MealRelation.withFood => 'With',
  MealRelation.after => 'PC',
};

/// A small selectable shorthand chip (frequency / timing / route).
class _ShChip extends StatelessWidget {
  const _ShChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppColors.accentSoftOn(context) : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primary.withValues(alpha: 0.45) : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ---- Lab tests ------------------------------------------------------------

class _TestChip extends StatelessWidget {
  const _TestChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? AppColors.accentSoftOn(context) : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary.withValues(alpha: 0.45) : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : scheme.onSurface,
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Icon(Icons.close_rounded, size: 15, color: AppColors.accentOn(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Follow-up ------------------------------------------------------------

class _DateField extends StatelessWidget {
  const _DateField({required this.date, required this.onTap, required this.onClear});

  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                date == null ? 'dd/mm/yyyy' : DateFormat('EEE, d MMM yyyy').format(date!),
                style: TextStyle(
                  fontSize: 15.5,
                  color: date == null ? scheme.onSurfaceVariant : scheme.onSurface,
                ),
              ),
            ),
            if (date != null)
              InkWell(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.close_rounded, size: 19, color: scheme.onSurfaceVariant),
                ),
              ),
            Icon(Icons.calendar_today_outlined, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/vitals_validators.dart';
import '../../../shared/widgets/error_view.dart';
import '../../medications/domain/med_shorthand.dart';
import '../data/clinician_repository.dart';
import '../domain/diagnosis_catalog.dart';
import '../domain/lab_catalog.dart';
import 'clinician_providers.dart';

/// The consultation flow: Vitals → Diagnosis → Clinical advice, ending in a
/// generated prescription. Vitals are recorded to the patient's history and the
/// complaint is carried onto the prescription; the diagnosis is a structured
/// pick-list; medicines use the clinic's shorthand and the labs its catalog.
class ConsultScreen extends ConsumerStatefulWidget {
  const ConsultScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<ConsultScreen> createState() => _ConsultScreenState();
}

class _ConsultScreenState extends ConsumerState<ConsultScreen> {
  static const _steps = ['Vitals', 'Diagnosis', 'Advice'];
  int _step = 0;

  // Vitals + complaint
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _systolic = TextEditingController();
  final _diastolic = TextEditingController();
  final _pulse = TextEditingController();
  final _sugar = TextEditingController();
  final _spo2 = TextEditingController();
  final _complaint = TextEditingController();

  // Diagnosis (stored labels) + free-text add
  final Set<String> _diagnoses = {};
  final _customDx = TextEditingController();

  // Medicines
  final List<_MedDraft> _meds = [_MedDraft()];

  // Labs + free-text add
  final Set<String> _labs = {};
  final _customTest = TextEditingController();

  // Advice + follow-up
  final _advice = TextEditingController();
  DateTime? _followUp;

  final _vitalsFormKey = GlobalKey<FormState>();
  AutovalidateMode _vitalsAutovalidate = AutovalidateMode.disabled;

  /// Whether the presenting complaint is printed on the prescription.
  bool _showComplaintOnRx = true;

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _height, _weight, _systolic, _diastolic, _pulse, _sugar, _spo2, _complaint,
      _customDx, _customTest, _advice,
    ]) {
      c.dispose();
    }
    for (final m in _meds) {
      m.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());
  double? _double(TextEditingController c) => double.tryParse(c.text.trim());

  bool get _hasMedicine => _meds.any((m) => m.name.text.trim().isNotEmpty);

  Future<void> _generate() async {
    // Bad vitals (out of range, or a diastolic ≥ systolic) block generation and
    // send the doctor back to the Vitals step to fix them.
    if (!(_vitalsFormKey.currentState?.validate() ?? true)) {
      setState(() {
        _step = 0;
        _vitalsAutovalidate = AutovalidateMode.onUserInteraction;
      });
      return;
    }
    if (!_hasMedicine) {
      setState(() {
        _step = 2;
        _error = 'Add at least one medicine before generating the prescription.';
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final complaint = _complaint.text.trim();
    final items = <Map<String, dynamic>>[];
    for (final m in _meds) {
      final name = m.name.text.trim();
      if (name.isEmpty) continue;
      items.add({
        'name': name,
        if (m.strength.text.trim().isNotEmpty) 'strength': m.strength.text.trim(),
        'frequency': m.frequency.apiFrequency,
        'relationToMeal': m.relation.api,
        'route': m.route.api,
        if (_int(m.duration) != null) 'durationDays': _int(m.duration),
        if (m.instructions.text.trim().isNotEmpty) 'instructions': m.instructions.text.trim(),
      });
    }

    final labs = <String>{..._labs};
    final customTest = _customTest.text.trim();
    if (customTest.isNotEmpty) labs.add(customTest);

    try {
      final repo = ref.read(clinicianRepositoryProvider);
      // Vitals first, so the measurements land in the record even if the doctor
      // backs out; then the prescription that references the complaint.
      await repo.recordConsultVitals(
        patientId: widget.patientId,
        complaint: complaint,
        heightCm: _double(_height),
        weightKg: _double(_weight),
        systolic: _int(_systolic),
        diastolic: _int(_diastolic),
        pulse: _int(_pulse),
        spo2: _int(_spo2),
        glucoseMgDl: _int(_sugar),
      );
      await repo.createPrescription(
        patientId: widget.patientId,
        items: items,
        // Recorded to the profile above regardless; only printed on the Rx when
        // the doctor left the checkbox ticked.
        complaint: (complaint.isEmpty || !_showComplaintOnRx) ? null : complaint,
        diagnosis: _diagnoses.toList(),
        labTestsAdvised: labs.toList(),
        generalAdvice: _advice.text.trim(),
        followUpOn: _followUp,
      );
      // The record, the medicine tracker and the history all just changed.
      ref.invalidate(patientPrescriptionsProvider(widget.patientId));
      ref.invalidate(patientSummaryProvider(widget.patientId));
      ref.invalidate(patientMedicationsProvider(widget.patientId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prescription created')),
      );
      // Land on the prescription list so the doctor can download the PDF.
      context.pushReplacement('/clinician/patients/${widget.patientId}/prescriptions', extra: widget.patientName);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorView.messageFor(context, e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Consult'),
        bottom: widget.patientName == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.patientName!,
                    style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
      ),
      body: Column(
        children: [
          _StepBar(step: _step, labels: _steps),
          Expanded(
            child: IndexedStack(
              index: _step,
              children: [_vitalsStep(), _diagnosisStep(), _adviceStep()],
            ),
          ),
          _navBar(),
        ],
      ),
    );
  }

  // ---- Step 1: Vitals --------------------------------------------------
  Widget _vitalsStep() {
    return Form(
      key: _vitalsFormKey,
      autovalidateMode: _vitalsAutovalidate,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const _StepTitle('Vitals', 'Measured at this visit — all optional'),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: _num(_height, 'Height', 'cm', VitalsValidators.height)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _num(_weight, 'Weight', 'kg', VitalsValidators.weight)),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: _num(_systolic, 'BP systolic', 'mmHg', VitalsValidators.systolic, integer: true)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _num(
                _diastolic,
                'BP diastolic',
                'mmHg',
                (v) => VitalsValidators.diastolic(v, systolicText: _systolic.text),
                integer: true,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Expanded(child: _num(_pulse, 'Heart rate', 'bpm', VitalsValidators.pulse, integer: true)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _num(_spo2, 'SpO₂', '%', VitalsValidators.spo2, integer: true)),
          ]),
          const SizedBox(height: AppSpacing.md),
          _num(_sugar, 'Blood sugar', 'mg/dL', VitalsValidators.sugar, integer: true),
          const SizedBox(height: AppSpacing.lg),
          const _StepTitle('Complaint', 'Add the reason for this visit'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _complaint,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Presenting complaint',
              alignLabelWithHint: true,
              hintText: 'e.g. increased thirst and fatigue for 2 weeks',
            ),
          ),
          CheckboxListTile(
            value: _showComplaintOnRx,
            onChanged: (v) => setState(() => _showComplaintOnRx = v ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.primary,
            title: const Text('Show this complaint on the prescription', style: TextStyle(fontSize: 14.5)),
          ),
        ],
      ),
    );
  }

  // ---- Step 2: Diagnosis ----------------------------------------------
  Widget _diagnosisStep() {
    final groups = diagnosisByCategory();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const _StepTitle('Diagnosis', 'Tap to select — printed on the prescription'),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 6),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in entry.value)
                _SelectChip(
                  label: d.code,
                  selected: _diagnoses.contains(d.label),
                  onTap: () => setState(() {
                    _diagnoses.contains(d.label) ? _diagnoses.remove(d.label) : _diagnoses.add(d.label);
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _customDx,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Add another diagnosis'),
                onSubmitted: (_) => _addCustomDx(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(onPressed: _addCustomDx, icon: const Icon(Icons.add)),
          ],
        ),
        if (_diagnoses.any((d) => kDiagnosisCatalog.every((o) => o.label != d))) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in _diagnoses.where((d) => kDiagnosisCatalog.every((o) => o.label != d)))
                Chip(
                  label: Text(d),
                  onDeleted: () => setState(() => _diagnoses.remove(d)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  void _addCustomDx() {
    final v = _customDx.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _diagnoses.add(v);
      _customDx.clear();
    });
  }

  // ---- Step 3: Clinical advice ----------------------------------------
  Widget _adviceStep() {
    final labGroups = labCatalogByCategory();
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        const _StepTitle('Medicines', 'The prescription — at least one needed'),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < _meds.length; i++)
          _MedCard(
            key: ObjectKey(_meds[i]),
            draft: _meds[i],
            index: i,
            onChanged: () => setState(() {}),
            onRemove: _meds.length == 1 ? null : () => setState(() => _meds.removeAt(i)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _meds.add(_MedDraft())),
            icon: const Icon(Icons.add),
            label: const Text('Add medicine'),
          ),
        ),

        const SizedBox(height: AppSpacing.md),
        const _StepTitle('Lab tests advised', 'Ordered with the prescription'),
        const SizedBox(height: AppSpacing.sm),
        for (final entry in labGroups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(
              entry.key,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in entry.value)
                _SelectChip(
                  label: p.name,
                  selected: _labs.contains(p.name),
                  onTap: () => setState(() {
                    _labs.contains(p.name) ? _labs.remove(p.name) : _labs.add(p.name);
                  }),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _customTest,
                decoration: const InputDecoration(labelText: 'Add another test'),
                onSubmitted: (_) => _addCustomTest(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filledTonal(onPressed: _addCustomTest, icon: const Icon(Icons.add)),
          ],
        ),

        const SizedBox(height: AppSpacing.lg),
        const _StepTitle('Lifestyle advice', 'Diet, activity, precautions'),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _advice,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Advice',
            alignLabelWithHint: true,
            hintText: 'e.g. reduce refined sugar, walk 30 min daily',
          ),
        ),

        const SizedBox(height: AppSpacing.md),
        InkWell(
          onTap: _pickFollowUp,
          borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Follow-up date',
              prefixIcon: Icon(Icons.event_outlined),
            ),
            child: Text(_followUp == null ? 'Not set' : DateFormat('d MMM yyyy').format(_followUp!)),
          ),
        ),
        if (_followUp != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => setState(() => _followUp = null), child: const Text('Clear')),
          ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.dangerBgOn(context),
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: AppColors.dangerOn(context), size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(_error!, style: TextStyle(color: AppColors.dangerOn(context)))),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _addCustomTest() {
    final v = _customTest.text.trim();
    if (v.isEmpty) return;
    setState(() {
      _labs.add(v);
      _customTest.clear();
    });
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUp ?? now.add(const Duration(days: 15)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _followUp = picked);
  }

  /// Advance a step. Leaving the Vitals step first validates it, so a bad
  /// measurement is caught before the doctor moves on.
  void _next() {
    if (_step == 0 && !(_vitalsFormKey.currentState?.validate() ?? true)) {
      setState(() => _vitalsAutovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    setState(() => _step += 1);
  }

  // ---- Nav + shared bits ----------------------------------------------
  Widget _navBar() {
    final last = _step == _steps.length - 1;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 8),
        child: Row(
          children: [
            if (_step > 0)
              OutlinedButton(
                onPressed: _submitting ? null : () => setState(() => _step -= 1),
                child: const Text('Back'),
              ),
            const Spacer(),
            if (!last)
              FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Next'),
              )
            else
              FilledButton.icon(
                onPressed: _submitting ? null : _generate,
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                icon: _submitting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_rounded),
                label: Text(_submitting ? 'Generating…' : 'Generate prescription'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _num(
    TextEditingController c,
    String label,
    String unit,
    String? Function(String?) validator, {
    bool integer = false,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      inputFormatters: [
        integer ? FilteringTextInputFormatter.digitsOnly : FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(labelText: label, suffixText: unit),
      validator: validator,
    );
  }
}

/// A mutable medicine draft — controllers plus the shorthand enums.
class _MedDraft {
  final name = TextEditingController();
  final strength = TextEditingController();
  final duration = TextEditingController();
  final instructions = TextEditingController();
  DoseFrequency frequency = DoseFrequency.od;
  MealRelation relation = MealRelation.after;
  MedRoute route = MedRoute.oral;

  void dispose() {
    name.dispose();
    strength.dispose();
    duration.dispose();
    instructions.dispose();
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({super.key, required this.draft, required this.index, required this.onChanged, this.onRemove});

  final _MedDraft draft;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shorthand = composeShorthand(frequency: draft.frequency, relation: draft.relation, route: draft.route);
    final plain = expandToPlain(frequency: draft.frequency, relation: draft.relation, route: draft.route);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: 'Medicine ${index + 1}', isDense: true),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                  tooltip: 'Remove',
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: draft.strength,
                  decoration: const InputDecoration(labelText: 'Strength', hintText: '500 mg', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  decoration: const InputDecoration(labelText: 'Days', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DoseFrequency>(
                  initialValue: draft.frequency,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Frequency', isDense: true),
                  items: [
                    for (final f in DoseFrequency.values)
                      DropdownMenuItem(value: f, child: Text('${f.code} · ${f.plain}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      draft.frequency = v;
                      onChanged();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<MedRoute>(
                  initialValue: draft.route,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Route', isDense: true),
                  items: [
                    for (final r in MedRoute.values)
                      DropdownMenuItem(value: r, child: Text(r.code, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      draft.route = v;
                      onChanged();
                    }
                  },
                ),
              ),
            ],
          ),
          if (draft.frequency.takesMealRelation) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<MealRelation>(
              initialValue: draft.relation,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Meal relation', isDense: true),
              items: const [
                DropdownMenuItem(value: MealRelation.after, child: Text('After food (PC)')),
                DropdownMenuItem(value: MealRelation.before, child: Text('Before food (AC)')),
                DropdownMenuItem(value: MealRelation.withFood, child: Text('With food')),
                DropdownMenuItem(value: MealRelation.anytime, child: Text('Anytime')),
              ],
              onChanged: (v) {
                if (v != null) {
                  draft.relation = v;
                  onChanged();
                }
              },
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$shorthand  ·  $plain',
              style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.labels});

  final int step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            _dot(context, i),
            if (i < labels.length - 1)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i < step ? AppColors.primary : scheme.outlineVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _dot(BuildContext context, int i) {
    final scheme = Theme.of(context).colorScheme;
    final done = i < step;
    final active = i == step;
    final color = (done || active) ? AppColors.primary : scheme.surfaceContainerHighest;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check, size: 15, color: Colors.white)
              : Text(
                  '${i + 1}',
                  style: TextStyle(
                    color: active ? Colors.white : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
        ),
        const SizedBox(width: 6),
        Text(
          labels[i],
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            color: active ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(subtitle, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SelectChip extends StatelessWidget {
  const _SelectChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 15, color: Colors.white),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

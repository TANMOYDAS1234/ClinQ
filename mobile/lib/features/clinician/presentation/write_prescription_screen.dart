import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/clinician_repository.dart';

/// Opens the prescription writer for [patientName]. Returns `true` if a
/// prescription was written (the server then mirrors it into the patient's
/// medication reminders automatically).
Future<bool?> showWritePrescription(BuildContext context, String patientId, String patientName) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => WritePrescriptionScreen(patientId: patientId, patientName: patientName),
    ),
  );
}

const _mealOptions = <({String value, String label})>[
  (value: 'after_meal', label: 'After food'),
  (value: 'before_meal', label: 'Before food'),
  (value: 'with_meal', label: 'With food'),
  (value: 'any', label: 'Anytime'),
];

/// Common frequencies, in the notation the backend turns into reminder times.
const _freqPresets = <String>['1-0-1', '1-0-0', '0-0-1', '1-1-1', '1-0-1-0'];

class _Item {
  final name = TextEditingController();
  final strength = TextEditingController();
  final dose = TextEditingController(text: '1 tablet');
  final frequency = TextEditingController(text: '1-0-1');
  final duration = TextEditingController();
  String meal = 'after_meal';

  void dispose() {
    name.dispose();
    strength.dispose();
    dose.dispose();
    frequency.dispose();
    duration.dispose();
  }
}

class WritePrescriptionScreen extends ConsumerStatefulWidget {
  const WritePrescriptionScreen({super.key, required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  ConsumerState<WritePrescriptionScreen> createState() => _WritePrescriptionScreenState();
}

class _WritePrescriptionScreenState extends ConsumerState<WritePrescriptionScreen> {
  final _diagnosis = TextEditingController();
  final _advice = TextEditingController();
  final List<_Item> _items = [_Item()];
  DateTime? _followUp;
  bool _saving = false;

  @override
  void dispose() {
    _diagnosis.dispose();
    _advice.dispose();
    for (final i in _items) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);

    final items = <Map<String, dynamic>>[];
    for (final it in _items) {
      final name = it.name.text.trim();
      if (name.isEmpty) continue;
      final durationDays = int.tryParse(it.duration.text.trim());
      items.add({
        'name': name,
        if (it.strength.text.trim().isNotEmpty) 'strength': it.strength.text.trim(),
        if (it.dose.text.trim().isNotEmpty) 'dose': it.dose.text.trim(),
        if (it.frequency.text.trim().isNotEmpty) 'frequency': it.frequency.text.trim(),
        if (durationDays != null && durationDays > 0) 'durationDays': durationDays,
        'relationToMeal': it.meal,
      });
    }

    if (items.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Add at least one medicine with a name')));
      return;
    }

    setState(() => _saving = true);
    try {
      final diagnosis = _diagnosis.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await ref.read(clinicianRepositoryProvider).createPrescription(
            patientId: widget.patientId,
            items: items,
            diagnosis: diagnosis,
            generalAdvice: _advice.text.trim(),
            followUpOn: _followUp,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Prescription sent · reminders set for the patient')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _followUp = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Prescribe · ${widget.patientName}'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('SAVE', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          TextField(
            controller: _diagnosis,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Diagnosis (optional)',
              hintText: 'e.g. Type 2 diabetes, Hypertension',
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Text('Medicines', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _items.add(_Item())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < _items.length; i++) _itemCard(i),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _advice,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Advice (optional)',
              hintText: 'e.g. Reduce sugar, walk 30 min daily',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined, color: AppColors.primary),
            title: const Text('Follow-up'),
            subtitle: Text(_followUp == null ? 'Not set' : DateFormat('EEE, d MMM yyyy').format(_followUp!)),
            trailing: TextButton(onPressed: _pickFollowUp, child: Text(_followUp == null ? 'Set' : 'Change')),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Widget _itemCard(int index) {
    final it = _items[index];
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: it.name,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Medicine ${index + 1} *',
                    hintText: 'e.g. Metformin',
                    isDense: true,
                  ),
                ),
              ),
              if (_items.length > 1)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => setState(() {
                    _items.removeAt(index).dispose();
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: it.strength,
                  decoration: const InputDecoration(labelText: 'Strength', hintText: '500 mg', isDense: true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: it.dose,
                  decoration: const InputDecoration(labelText: 'Dose', hintText: '1 tablet', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: it.frequency,
                  decoration: const InputDecoration(labelText: 'Frequency', hintText: '1-0-1', isDense: true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 96,
                child: TextField(
                  controller: it.duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Days', hintText: '30', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 6,
            children: [
              for (final f in _freqPresets)
                ActionChip(
                  label: Text(f, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => it.frequency.text = f),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: it.meal,
            decoration: const InputDecoration(labelText: 'When', isDense: true),
            items: [for (final m in _mealOptions) DropdownMenuItem(value: m.value, child: Text(m.label))],
            onChanged: (v) => setState(() => it.meal = v ?? 'after_meal'),
          ),
        ],
      ),
    );
  }
}

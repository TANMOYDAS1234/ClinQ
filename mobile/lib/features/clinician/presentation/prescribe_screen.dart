import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/clinician_repository.dart';

/// The doctor's prescribe form. Each medicine becomes an entry in the patient's
/// medication tracker (with dose-time reminders) automatically; lab tests advised
/// tell the patient which reports to get done next.
class PrescribeScreen extends ConsumerStatefulWidget {
  const PrescribeScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<PrescribeScreen> createState() => _PrescribeScreenState();
}

class _PrescribeScreenState extends ConsumerState<PrescribeScreen> {
  final List<_MedItem> _meds = [_MedItem()];
  final _diagnosis = TextEditingController();
  final _labTests = TextEditingController();
  final _advice = TextEditingController();
  DateTime? _followUp;
  bool _saving = false;

  @override
  void dispose() {
    for (final m in _meds) {
      m.dispose();
    }
    _diagnosis.dispose();
    _labTests.dispose();
    _advice.dispose();
    super.dispose();
  }

  void _addMedicine() => setState(() => _meds.add(_MedItem()));

  void _removeMedicine(int i) {
    setState(() {
      _meds[i].dispose();
      _meds.removeAt(i);
    });
  }

  List<String> _splitList(String raw) =>
      raw.split(RegExp(r'[,\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _save() async {
    final items = _meds
        .where((m) => m.name.text.trim().isNotEmpty)
        .map((m) => <String, dynamic>{
              'name': m.name.text.trim(),
              if (m.strength.text.trim().isNotEmpty) 'strength': m.strength.text.trim(),
              if (m.dose.text.trim().isNotEmpty) 'dose': m.dose.text.trim(),
              'frequency': m.frequency,
              'relationToMeal': m.relationToMeal,
              if (int.tryParse(m.duration.text.trim()) != null)
                'durationDays': int.parse(m.duration.text.trim()),
              if (m.instructions.text.trim().isNotEmpty) 'instructions': m.instructions.text.trim(),
            })
        .toList();

    final messenger = ScaffoldMessenger.of(context);
    if (items.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Add at least one medicine (a name is required).')));
      return;
    }

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      await ref.read(clinicianRepositoryProvider).createPrescription(
            patientId: widget.patientId,
            items: items,
            diagnosis: _splitList(_diagnosis.text),
            labTestsAdvised: _splitList(_labTests.text),
            generalAdvice: _advice.text.trim().isEmpty ? null : _advice.text.trim(),
            followUpOn: _followUp,
          );
      messenger.showSnackBar(const SnackBar(content: Text('Prescription sent — added to the patient’s tracker')));
      navigator.pop(true);
    } on ApiException catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prescribe'),
        bottom: widget.patientName == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: AppSpacing.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('for ${widget.patientName}',
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  ),
                ),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
        children: [
          for (var i = 0; i < _meds.length; i++) ...[
            _MedCard(
              item: _meds[i],
              index: i + 1,
              onRemove: _meds.length > 1 ? () => _removeMedicine(i) : null,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          OutlinedButton.icon(
            onPressed: _addMedicine,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add another medicine'),
          ),
          const SizedBox(height: AppSpacing.lg),
          _fieldCard(
            scheme,
            icon: Icons.biotech_outlined,
            label: 'Lab tests advised',
            hint: 'e.g. HbA1c, Lipid profile, Serum creatinine',
            controller: _labTests,
            help: 'The patient will see these as tests to get done.',
          ),
          const SizedBox(height: AppSpacing.md),
          _fieldCard(
            scheme,
            icon: Icons.medical_information_outlined,
            label: 'Diagnosis',
            hint: 'e.g. Type 2 diabetes, Hypertension',
            controller: _diagnosis,
          ),
          const SizedBox(height: AppSpacing.md),
          _fieldCard(
            scheme,
            icon: Icons.tips_and_updates_outlined,
            label: 'General advice',
            hint: 'Diet, activity, warning signs…',
            controller: _advice,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),
          _FollowUpTile(
            date: _followUp,
            onPick: (d) => setState(() => _followUp = d),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.primary,
          ),
          child: _saving
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : const Text('Send prescription', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _fieldCard(
    ColorScheme scheme, {
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    int maxLines = 1,
    String? help,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(hintText: hint, isDense: true),
          ),
          if (help != null) ...[
            const SizedBox(height: 6),
            Text(help, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MedItem {
  final name = TextEditingController();
  final strength = TextEditingController();
  final dose = TextEditingController();
  final duration = TextEditingController();
  final instructions = TextEditingController();
  String frequency = '1-0-1';
  String relationToMeal = 'any';

  void dispose() {
    name.dispose();
    strength.dispose();
    dose.dispose();
    duration.dispose();
    instructions.dispose();
  }
}

const _frequencies = <(String, String)>[
  ('1-0-0', 'Morning'),
  ('0-1-0', 'Noon'),
  ('0-0-1', 'Night'),
  ('1-0-1', 'Morn + Night'),
  ('1-1-1', 'Thrice'),
];

const _meals = <(String, String)>[
  ('before_meal', 'Before food'),
  ('after_meal', 'After food'),
  ('with_meal', 'With food'),
  ('any', 'Anytime'),
];

class _MedCard extends StatelessWidget {
  const _MedCard({required this.item, required this.index, required this.onRemove, required this.onChanged});

  final _MedItem item;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.11), shape: BoxShape.circle),
                child: Text('$index',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary)),
              ),
              const SizedBox(width: 8),
              const Text('Medicine', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(Icons.close_rounded, size: 20, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: item.name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name *', hintText: 'e.g. Metformin', isDense: true),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: item.strength,
                  decoration: const InputDecoration(labelText: 'Strength', hintText: '500 mg', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: item.dose,
                  decoration: const InputDecoration(labelText: 'Dose', hintText: '1 tablet', isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _chipLabel('Frequency'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _frequencies)
                ChoiceChip(
                  label: Text('$value · $label'),
                  selected: item.frequency == value,
                  onSelected: (_) {
                    item.frequency = value;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          _chipLabel('When'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in _meals)
                ChoiceChip(
                  label: Text(label),
                  selected: item.relationToMeal == value,
                  onSelected: (_) {
                    item.relationToMeal = value;
                    onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: item.duration,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Days', hintText: '30', isDense: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: item.instructions,
                  decoration: const InputDecoration(labelText: 'Instructions', hintText: 'optional', isDense: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chipLabel(String text) =>
      Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.primary));
}

class _FollowUpTile extends StatelessWidget {
  const _FollowUpTile({required this.date, required this.onPick});

  final DateTime? date;
  final ValueChanged<DateTime?> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListTile(
        leading: const Icon(Icons.event_outlined, color: AppColors.primary),
        title: const Text('Follow-up date', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Text(date == null ? 'Optional' : DateFormat('EEE, d MMM yyyy').format(date!),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        trailing: date == null
            ? const Icon(Icons.chevron_right_rounded)
            : IconButton(icon: const Icon(Icons.clear_rounded), onPressed: () => onPick(null)),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? now.add(const Duration(days: 14)),
            firstDate: now,
            lastDate: DateTime(now.year + 2),
          );
          if (picked != null) onPick(picked);
        },
      ),
    );
  }
}

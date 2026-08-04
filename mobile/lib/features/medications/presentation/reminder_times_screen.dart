import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/core_providers.dart';
import '../data/medications_repository.dart';
import '../domain/medication.dart';
import 'medications_providers.dart';

String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _parse(String hhmm, TimeOfDay fallback) {
  final parts = hhmm.split(':');
  if (parts.length == 2) {
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h != null && m != null && h < 24 && m < 60) return TimeOfDay(hour: h, minute: m);
  }
  return fallback;
}

/// Where the patient tunes when their reminders fire: their meal times (which
/// "before/after food" doses are anchored to) and, for the odd medicine, an
/// exact per-dose time override.
class ReminderTimesScreen extends ConsumerStatefulWidget {
  const ReminderTimesScreen({super.key});

  @override
  ConsumerState<ReminderTimesScreen> createState() => _ReminderTimesScreenState();
}

class _ReminderTimesScreenState extends ConsumerState<ReminderTimesScreen> {
  bool _loading = true;
  bool _savingMeals = false;
  TimeOfDay _breakfast = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _lunch = const TimeOfDay(hour: 13, minute: 30);
  TimeOfDay _dinner = const TimeOfDay(hour: 20, minute: 30);
  List<Medication> _meds = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final json = await ref.read(apiClientProvider).getJson('/auth/me');
      final profile = json['profile'] as Map<String, dynamic>? ?? const {};
      final meals = profile['mealTimes'] as Map<String, dynamic>? ?? const {};
      final meds = await ref.read(medicationsRepositoryProvider).getMedications();
      if (!mounted) return;
      setState(() {
        _breakfast = _parse(meals['breakfast']?.toString() ?? '', _breakfast);
        _lunch = _parse(meals['lunch']?.toString() ?? '', _lunch);
        _dinner = _parse(meals['dinner']?.toString() ?? '', _dinner);
        _meds = meds.where((m) => m.isActive).toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickMeal(String which) async {
    final current = switch (which) { 'breakfast' => _breakfast, 'lunch' => _lunch, _ => _dinner };
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    setState(() {
      if (which == 'breakfast') {
        _breakfast = picked;
      } else if (which == 'lunch') {
        _lunch = picked;
      } else {
        _dinner = picked;
      }
    });
  }

  Future<void> _saveMeals() async {
    setState(() => _savingMeals = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).patchJson('/auth/me/profile', body: {
        'mealTimes': {'breakfast': _fmt(_breakfast), 'lunch': _fmt(_lunch), 'dinner': _fmt(_dinner)},
      });
      await _afterChange();
      messenger.showSnackBar(const SnackBar(content: Text('Meal times saved — reminders updated')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _savingMeals = false);
    }
  }

  Future<void> _editMedTime(Medication med, int index) async {
    final entry = med.schedule[index];
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showTimePicker(context: context, initialTime: _parse(entry.time, const TimeOfDay(hour: 8, minute: 0)));
    if (picked == null) return;
    final schedule = [
      for (var i = 0; i < med.schedule.length; i++)
        {
          'time': i == index ? _fmt(picked) : med.schedule[i].time,
          'relationToMeal': med.schedule[i].relationToMeal,
        },
    ];
    try {
      await ref.read(medicationsRepositoryProvider).updateSchedule(med.id, schedule);
      await _afterChange();
      messenger.showSnackBar(SnackBar(content: Text('${med.name} reminder updated')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Reload the medicines and re-arm the on-device alarms after any change.
  Future<void> _afterChange() async {
    ref.invalidate(todayScheduleProvider);
    ref.invalidate(medicationsListProvider);
    final meds = await ref.read(medicationsRepositoryProvider).getMedications();
    await syncMedicationReminders(meds);
    if (mounted) setState(() => _meds = meds.where((m) => m.isActive).toList());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminder times')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Text('YOUR MEAL TIMES', style: _label(scheme)),
                const SizedBox(height: 6),
                Text('Reminders like "before breakfast" fire around these times.',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.sm),
                _card(scheme, [
                  _mealRow('Breakfast', _breakfast, () => _pickMeal('breakfast'), scheme),
                  _divider(scheme),
                  _mealRow('Lunch', _lunch, () => _pickMeal('lunch'), scheme),
                  _divider(scheme),
                  _mealRow('Dinner', _dinner, () => _pickMeal('dinner'), scheme),
                ]),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _savingMeals ? null : _saveMeals,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.primary),
                  child: _savingMeals
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                      : const Text('Save meal times'),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text('EXACT TIME PER MEDICINE', style: _label(scheme)),
                const SizedBox(height: 6),
                Text('Override a specific dose time. This stays fixed even if you change your meal times.',
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.sm),
                if (_meds.isEmpty)
                  _card(scheme, [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text('No active medicines yet.', style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  ])
                else
                  for (final med in _meds) ...[
                    _MedTimes(med: med, onEdit: (i) => _editMedTime(med, i)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
    );
  }

  TextStyle _label(ColorScheme scheme) =>
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: scheme.onSurfaceVariant);

  Widget _card(ColorScheme scheme, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _divider(ColorScheme scheme) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4));

  Widget _mealRow(String label, TimeOfDay time, VoidCallback onTap, ColorScheme scheme) => ListTile(
        title: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        trailing: Text(time.format(context), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
        onTap: onTap,
      );
}

class _MedTimes extends StatelessWidget {
  const _MedTimes({required this.med, required this.onEdit});

  final Medication med;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
          Text(med.name, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < med.schedule.length; i++)
                ActionChip(
                  avatar: const Icon(Icons.access_time_rounded, size: 16, color: AppColors.primary),
                  label: Text(med.schedule[i].time),
                  onPressed: () => onEdit(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

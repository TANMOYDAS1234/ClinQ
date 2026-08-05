import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../appointments/data/clinic_repository.dart';
import '../../appointments/domain/clinic.dart';
import '../../appointments/presentation/appointment_providers.dart';

const _weekOrder = [1, 2, 3, 4, 5, 6, 0]; // Mon … Sun
const _dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/// Create or edit a clinic: its details, slot length, weekly availability
/// windows and one-off closures. Doctor + staff.
class ClinicEditScreen extends ConsumerStatefulWidget {
  const ClinicEditScreen({super.key, this.clinic});

  final Clinic? clinic;

  @override
  ConsumerState<ClinicEditScreen> createState() => _ClinicEditScreenState();
}

class _ClinicEditScreenState extends ConsumerState<ClinicEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _phone;
  late final TextEditingController _mapUrl;

  int _slotMinutes = 15;
  bool _isActive = true;
  late List<WeeklyHour> _weekly;
  late List<ClinicOverride> _overrides;
  bool _saving = false;

  bool get _editing => widget.clinic != null;

  @override
  void initState() {
    super.initState();
    final c = widget.clinic;
    _name = TextEditingController(text: c?.name ?? '');
    _address = TextEditingController(text: c?.addressLine ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _mapUrl = TextEditingController(text: c?.mapUrl ?? '');
    _slotMinutes = c?.slotMinutes ?? 15;
    _isActive = c?.isActive ?? true;
    _weekly = [...?c?.weeklyHours];
    _overrides = [...?c?.overrides];
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _phone.dispose();
    _mapUrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _addWindow(int day) async {
    final start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
      helpText: 'Start time',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute),
      helpText: 'End time',
    );
    if (end == null || !mounted) return;
    final s = _fmt(start);
    final e = _fmt(end);
    if (e.compareTo(s) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End time must be after the start time')));
      return;
    }
    setState(() => _weekly.add(WeeklyHour(dayOfWeek: day, start: s, end: e)));
  }

  void _removeWindow(WeeklyHour w) {
    setState(() => _weekly.remove(w));
  }

  Future<void> _addClosure() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 1),
      helpText: 'Closed on',
    );
    if (picked == null) return;
    final date = DateFormat('yyyy-MM-dd').format(picked);
    if (_overrides.any((o) => o.date == date)) return;
    setState(() => _overrides.add(ClinicOverride(date: date, isClosed: true)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    final body = {
      'name': _name.text.trim(),
      'addressLine': _address.text.trim(),
      'city': _city.text.trim(),
      'phone': _phone.text.trim(),
      'mapUrl': _mapUrl.text.trim(),
      'slotMinutes': _slotMinutes,
      'weeklyHours': _weekly.map((w) => w.toJson()).toList(),
      'overrides': _overrides.map((o) => o.toJson()).toList(),
      'isActive': _isActive,
    };

    try {
      final repo = ref.read(clinicRepositoryProvider);
      if (_editing) {
        await repo.update(widget.clinic!.id, body);
      } else {
        await repo.create(body);
      }
      ref.invalidate(clinicsProvider);
      ref.invalidate(clinicPhoneProvider); // so every "Call clinic" picks up the new number at once
      messenger.showSnackBar(const SnackBar(content: Text('Clinic saved')));
      navigator.pop();
    } on ApiException catch (e) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate clinic?'),
        content: const Text('It will stop accepting new bookings. Existing appointments are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(clinicRepositoryProvider).deactivate(widget.clinic!.id);
      ref.invalidate(clinicsProvider);
      navigator.pop();
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not deactivate. Please try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit clinic' : 'Add clinic'),
        actions: [
          if (_editing)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Deactivate',
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 96),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Clinic name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _city, decoration: const InputDecoration(labelText: 'City'))),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone'))),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(controller: _mapUrl, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Map link (optional)')),
            const SizedBox(height: AppSpacing.lg),

            // Slot length.
            Text('Slot length', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final m in [10, 15, 20, 30, 45])
                  ChoiceChip(
                    label: Text('$m min'),
                    selected: _slotMinutes == m,
                    onSelected: (_) => setState(() => _slotMinutes = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('Accepting bookings'),
              subtitle: const Text('Patients can book this clinic when on'),
            ),
            const Divider(height: AppSpacing.xl),

            // Weekly availability.
            const Text('Weekly availability', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.xs),
            Text('Set the times the doctor is available each day. Slots are generated inside these windows.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.md),
            for (final day in _weekOrder) _DayEditor(
              dayName: _dayNames[day],
              windows: (_weekly.where((w) => w.dayOfWeek == day).toList())..sort((a, b) => a.start.compareTo(b.start)),
              onAdd: () => _addWindow(day),
              onRemove: _removeWindow,
            ),
            const Divider(height: AppSpacing.xl),

            // Closures.
            Row(
              children: [
                const Expanded(child: Text('Closures & holidays', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                TextButton.icon(onPressed: _addClosure, icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add')),
              ],
            ),
            if (_overrides.isEmpty)
              Text('No closures set', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant))
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final o in _overrides.where((o) => o.isClosed))
                    InputChip(
                      label: Text(DateFormat('d MMM yyyy').format(DateTime.parse(o.date))),
                      onDeleted: () => setState(() => _overrides.remove(o)),
                    ),
                ],
              ),
          ],
        ),
      ),
      bottomSheet: Container(
        padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                : Text(_editing ? 'Save changes' : 'Create clinic', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

class _DayEditor extends StatelessWidget {
  const _DayEditor({required this.dayName, required this.windows, required this.onAdd, required this.onRemove});

  final String dayName;
  final List<WeeklyHour> windows;
  final VoidCallback onAdd;
  final ValueChanged<WeeklyHour> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 84, child: Padding(padding: const EdgeInsets.only(top: 8), child: Text(dayName, style: const TextStyle(fontWeight: FontWeight.w700)))),
            Expanded(
              child: windows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('Closed', style: TextStyle(color: scheme.onSurfaceVariant)),
                    )
                  : Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: 4,
                      children: [
                        for (final w in windows)
                          InputChip(
                            label: Text('${w.start} – ${w.end}'),
                            onDeleted: () => onRemove(w),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded, color: AppColors.accentOn(context)),
              tooltip: 'Add hours',
              onPressed: onAdd,
            ),
          ],
        ),
      ),
    );
  }
}

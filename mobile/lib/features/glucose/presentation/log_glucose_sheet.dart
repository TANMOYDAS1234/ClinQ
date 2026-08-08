import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/glucose_repository.dart';
import 'glucose_providers.dart';

class _ContextOption {
  const _ContextOption(this.value, this.labelBuilder);
  final String value;
  final String Function(AppLocalizations) labelBuilder;
}

final _contextOptions = [
  _ContextOption('fasting', (l) => l.glucoseContextFasting),
  _ContextOption('pre_meal', (l) => l.glucoseContextPreMeal),
  _ContextOption('post_meal', (l) => l.glucoseContextPostMeal),
  _ContextOption('bedtime', (l) => l.glucoseContextBedtime),
  _ContextOption('random', (l) => l.glucoseContextRandom),
];

/// Opened as a modal bottom sheet from the Track tab.
Future<void> showLogGlucoseSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _LogGlucoseSheet(),
  );
}

class _LogGlucoseSheet extends ConsumerStatefulWidget {
  const _LogGlucoseSheet();

  @override
  ConsumerState<_LogGlucoseSheet> createState() => _LogGlucoseSheetState();
}

class _LogGlucoseSheetState extends ConsumerState<_LogGlucoseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  final _notesController = TextEditingController();
  String _context = 'fasting';
  DateTime _measuredAt = DateTime.now();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _measuredAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_measuredAt),
    );
    if (time == null) return;
    setState(() {
      _measuredAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(glucoseRepositoryProvider)
          .logReading(
            valueMgDl: num.parse(_valueController.text.trim()),
            context: _context,
            measuredAt: _measuredAt,
            notes: _notesController.text.trim(),
          );
      ref.invalidate(glucoseReadingsProvider);
      ref.invalidate(glucoseTrendsProvider);
      // Push the adaptive check-in nudge forward from this reading, so a patient
      // who logs on cadence never actually sees it.
      unawaited(syncCheckInReminder(ref, knownLast: _measuredAt));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.glucoseReadingSaved)));
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = ErrorView.messageFor(context, e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.glucoseLogReading, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _valueController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.glucoseValueLabel),
              validator: (v) {
                final parsed = num.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) return l10n.commonRequiredField;
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.glucoseContextLabel, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _contextOptions.map((opt) {
                final selected = opt.value == _context;
                return ChoiceChip(
                  label: Text(opt.labelBuilder(l10n)),
                  selected: selected,
                  onSelected: (_) => setState(() => _context = opt.value),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: _pickDateTime,
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              child: InputDecorator(
                decoration: InputDecoration(labelText: l10n.glucoseTimeLabel),
                child: Text(
                  '${_measuredAt.year}-${_measuredAt.month.toString().padLeft(2, '0')}-'
                  '${_measuredAt.day.toString().padLeft(2, '0')}  '
                  '${_measuredAt.hour.toString().padLeft(2, '0')}:${_measuredAt.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(labelText: l10n.glucoseNotesLabel),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppButton(label: l10n.glucoseSaveReading, isLoading: _isSubmitting, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/fullscreen_photo.dart';
import '../../clinician/domain/patient_summary.dart';
import '../../foodlog/domain/food_log.dart';
import '../domain/diet_models.dart';
import 'dietician_patients_screen.dart' show dietRiskColor;
import 'dietician_providers.dart';

/// What the dietician needs to recommend food safely: the patient's medical
/// status and the doctor's current medicine list. Food advice is given in the
/// care chat (the "Message" button), informed by the food log.
class DieticianPatientScreen extends ConsumerWidget {
  const DieticianPatientScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietOverviewProvider(patientId));

    return Scaffold(
      appBar: AppBar(title: Text(patientName ?? 'Patient')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load this patient'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: () => ref.invalidate(dietOverviewProvider(patientId)), child: const Text('Retry')),
            ],
          ),
        ),
        data: (o) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(dietOverviewProvider(patientId)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 110),
            children: [
              _MedicalCard(overview: o),
              const SizedBox(height: AppSpacing.lg),
              // Above the medicines and the log on purpose: the plan is what the
              // dietician is here to produce; everything below it is input.
              _SectionTitle('Diet plan'),
              const SizedBox(height: AppSpacing.sm),
              _DietPlanSection(patientId: patientId, patientName: patientName ?? o.name),
              if (o.vitals?.hasAny ?? false) ...[
                const SizedBox(height: AppSpacing.lg),
                _SectionTitle('Vitals & measurements'),
                const SizedBox(height: AppSpacing.sm),
                _VitalsSection(vitals: o.vitals!),
              ],
              const SizedBox(height: AppSpacing.lg),
              _SectionTitle('Current medicines', trailing: '${o.medications.length}'),
              const SizedBox(height: AppSpacing.sm),
              if (o.medications.isEmpty)
                _emptyNote(scheme, 'No medicines on record from the doctor yet.')
              else
                Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < o.medications.length; i++) ...[
                        if (i > 0) Divider(height: 1, indent: 56, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                        _MedRow(med: o.medications[i]),
                      ],
                    ],
                  ),
                ),
              if (o.advice.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _SectionTitle('Doctor’s advice'),
                const SizedBox(height: AppSpacing.sm),
                _AdviceSection(advice: o.advice),
              ],
              if (o.advisedTests.isNotEmpty || o.latestHba1c != null) ...[
                const SizedBox(height: AppSpacing.lg),
                _SectionTitle('Tests ordered by the doctor'),
                const SizedBox(height: AppSpacing.sm),
                _LabTests(overview: o),
              ],
              if (o.labReports.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                _SectionTitle('Lab reports', trailing: '${o.labReports.length}'),
                const SizedBox(height: AppSpacing.sm),
                _LabReportsSection(reports: o.labReports),
              ],
              const SizedBox(height: AppSpacing.lg),
              _SectionTitle('Food log'),
              const SizedBox(height: AppSpacing.sm),
              _FoodLogSection(patientId: patientId),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(AppSpacing.md),
        child: FilledButton.icon(
          onPressed: () => context.push('/dietician/patients/$patientId/chat', extra: patientName),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.primary),
          icon: const Icon(Icons.forum_rounded),
          label: const Text('Message patient', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _emptyNote(ColorScheme scheme, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
      );
}

class _MedicalCard extends StatelessWidget {
  const _MedicalCard({required this.overview});

  final DietPatientOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final o = overview;
    final risk = AppColors.toneOn(context, dietRiskColor(o.riskBand));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accentOn(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(o.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: risk.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(20)),
                child: Text('${o.riskBand[0].toUpperCase()}${o.riskBand.substring(1)} risk',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: risk)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _fact('Diabetes', o.diabetesType ?? '—', scheme),
              if (o.age != null) _fact('Age', '${o.age} yrs', scheme),
              if (o.gender != null && o.gender!.isNotEmpty) _fact('Gender', o.gender!, scheme),
              if (o.heightCm != null) _fact('Height', '${o.heightCm} cm', scheme),
              if (o.diagnosedOn != null) _fact('Diagnosed', DateFormat('MMM yyyy').format(o.diagnosedOn!), scheme),
              if (o.reviewIntervalDays != null) _fact('Review every', '${o.reviewIntervalDays} days', scheme),
            ],
          ),
          if (o.chiefComplaint != null) ...[
            const SizedBox(height: 12),
            Text('MAIN CONCERN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(o.chiefComplaint!, style: const TextStyle(fontSize: 14, height: 1.35)),
          ],
          if (o.allergies.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('ALLERGIES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in o.allergies)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.dangerOn(context).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                    child: Text(a, style: TextStyle(fontSize: 12.5, color: AppColors.dangerOn(context), fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value, ColorScheme scheme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        ],
      );
}

class _MedRow extends StatelessWidget {
  const _MedRow({required this.med});

  final DietMed med;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sub = [
      if (med.strength.isNotEmpty) med.strength,
      if (med.dose.isNotEmpty) med.dose,
      if (med.times.isNotEmpty) med.times.join(', '),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppColors.accentOn(context).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
            child: Icon(Icons.medication_rounded, size: 18, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(med.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// The plan at a glance, with the one thing that matters most about it: whether
/// the patient has actually been sent it. A finished-looking plan the patient
/// has never seen is a draft, and the card says so rather than looking done.
class _DietPlanSection extends ConsumerWidget {
  const _DietPlanSection({required this.patientId, required this.patientName});

  final String patientId;
  final String patientName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietPlanProvider(patientId));

    void open() => context.push('/dietician/patients/$patientId/diet', extra: patientName);

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _note(scheme, 'Could not load the diet plan.'),
      data: (plan) {
        if (plan == null || plan.isEmpty) {
          return Material(
            color: scheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: open,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.restaurant_menu_rounded, color: scheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('No plan yet', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            'Write one so the advice survives the conversation.',
                            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          );
        }

        return Material(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: open,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: plan.hasUnsentChanges
                      ? AppColors.warning.withValues(alpha: 0.55)
                      : scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          plan.goal.isNotEmpty ? plan.goal : '${plan.meals.length} meals planned',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.35),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.edit_outlined, size: 19, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 6,
                    children: [
                      for (final meal in plan.meals.take(5))
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoftOn(context),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            meal.time.isNotEmpty ? '${meal.name} · ${meal.time}' : meal.name,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accentOn(context),
                            ),
                          ),
                        ),
                      if (plan.avoid.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.dangerOn(context).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${plan.avoid.length} to avoid',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dangerOn(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        plan.hasUnsentChanges ? Icons.schedule_rounded : Icons.check_circle_rounded,
                        size: 16,
                        color: plan.hasUnsentChanges ? AppColors.warning : AppColors.primary,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          plan.sharedAt == null
                              ? 'Not sent to the patient yet'
                              : plan.hasUnsentChanges
                              ? 'Edited since it was last sent'
                              : 'Sent ${DateFormat('d MMM').format(plan.sharedAt!)}'
                                    '${plan.dieticianName != null ? ' · ${plan.dieticianName}' : ''}',
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _note(ColorScheme scheme, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ),
    child: Text(text, style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
  );
}

class _FoodLogSection extends ConsumerWidget {
  const _FoodLogSection({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietFoodLogProvider(patientId));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator())),
      error: (_, _) => _note(scheme, 'Could not load the food log.'),
      data: (entries) {
        if (entries.isEmpty) return _note(scheme, 'No meals logged yet.');
        return Column(
          children: [
            for (final e in entries.take(30))
              Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _FoodEntry(entry: e)),
          ],
        );
      },
    );
  }

  Widget _note(ColorScheme scheme, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
      );
}

class _FoodEntry extends StatelessWidget {
  const _FoodEntry({required this.entry});

  final FoodLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meal = entry.mealType.isEmpty ? 'Meal' : '${entry.mealType[0].toUpperCase()}${entry.mealType.substring(1)}';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AuthedImage(path: entry.photoUrl!, width: 56, height: 56, radius: 10),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(meal, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentOn(context))),
                    const Spacer(),
                    if (entry.createdAt != null)
                      Text(DateFormat('d MMM, h:mm a').format(entry.createdAt!), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
                if (entry.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(entry.note, style: const TextStyle(fontSize: 14)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lab work the doctor ordered, with whether a result is actually back.
///
/// The pending ones matter as much as the returned: a plan written while an
/// HbA1c is still outstanding is a plan resting on a number nobody has, and the
/// dietician should be able to see that before they write it.
class _LabTests extends StatelessWidget {
  const _LabTests({required this.overview});

  final DietPatientOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hba1c = overview.latestHba1c;

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
          if (hba1c != null) ...[
            Row(
              children: [
                Icon(Icons.science_outlined, size: 19, color: AppColors.accentOn(context)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Last HbA1c  $hba1c%',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (overview.hba1cTestedOn != null)
                  Text(
                    DateFormat('MMM yyyy').format(overview.hba1cTestedOn!),
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            if (overview.advisedTests.isNotEmpty) const Divider(height: AppSpacing.lg),
          ],
          for (final test in overview.advisedTests)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(
                    test.reported ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    size: 17,
                    color: test.reported ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(test.name, style: const TextStyle(fontSize: 14.5))),
                  Text(
                    test.reported ? 'Result in' : 'Awaiting result',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: test.reported ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The patient's latest real vitals & measurements — each its own most-recent
/// reading with the date it was taken. Only what was actually recorded shows;
/// a never-recorded measurement is simply absent, never a fabricated figure.
class _VitalsSection extends StatelessWidget {
  const _VitalsSection({required this.vitals});

  final DietVitals vitals;

  static String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  static String _glucoseLabel(String? ctx) => switch (ctx) {
        'fasting' => 'Fasting sugar',
        'pre_meal' => 'Pre-meal sugar',
        'post_meal' => 'Post-meal sugar',
        'bedtime' => 'Bedtime sugar',
        'hypo_check' => 'Hypo check',
        _ => 'Blood sugar',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = vitals;
    final tiles = <Widget>[
      if (v.bloodPressure != null)
        _MeasureTile(label: 'Blood pressure', value: v.bloodPressure!.label, unit: 'mmHg', at: v.bloodPressure!.at, danger: v.bloodPressure!.isHigh),
      if (v.glucose != null)
        _MeasureTile(label: _glucoseLabel(v.glucose!.context), value: _n(v.glucose!.valueMgDl), unit: 'mg/dL', at: v.glucose!.at, danger: v.glucose!.isAbnormal),
      if (v.weightKg != null) _MeasureTile(label: 'Weight', value: _n(v.weightKg!.value), unit: 'kg', at: v.weightKg!.at),
      if (v.bmi != null) _MeasureTile(label: 'BMI', value: _n(v.bmi!), unit: '', at: null),
      if (v.waistCm != null) _MeasureTile(label: 'Waist', value: _n(v.waistCm!.value), unit: 'cm', at: v.waistCm!.at),
      if (v.pulse != null) _MeasureTile(label: 'Pulse', value: _n(v.pulse!.value), unit: 'bpm', at: v.pulse!.at),
      if (v.spo2 != null) _MeasureTile(label: 'SpO₂', value: _n(v.spo2!.value), unit: '%', at: v.spo2!.at),
      if (v.temperatureC != null) _MeasureTile(label: 'Temp', value: _n(v.temperatureC!.value), unit: '°C', at: v.temperatureC!.at),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - AppSpacing.md) / 2;
          return Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [for (final t in tiles) SizedBox(width: w, child: t)],
          );
        },
      ),
    );
  }
}

class _MeasureTile extends StatelessWidget {
  const _MeasureTile({required this.label, required this.value, required this.unit, this.at, this.danger = false});

  final String label;
  final String value;
  final String unit;
  final DateTime? at;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final valueColor = danger ? AppColors.dangerOn(context) : scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: valueColor))),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
        if (at != null) ...[
          const SizedBox(height: 2),
          Text(DateFormat('d MMM yyyy').format(at!), style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// The doctor's advice and diagnosis over time — one collapsible entry per
/// prescription, so the dietician plans with the clinical reasoning in view.
class _AdviceSection extends StatelessWidget {
  const _AdviceSection({required this.advice});

  final List<DietAdvice> advice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < advice.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            _AdviceTile(entry: advice[i]),
          ],
        ],
      ),
    );
  }
}

class _AdviceTile extends StatelessWidget {
  const _AdviceTile({required this.entry});

  final DietAdvice entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = entry.issuedOn != null ? DateFormat('d MMM yyyy').format(entry.issuedOn!) : '—';
    final dx = entry.diagnosis.join(', ');
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(date, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
          dx.isNotEmpty ? dx : (entry.doctorName ?? 'Advice on record'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        children: [
          if (entry.diagnosis.isNotEmpty) _kv(scheme, 'Diagnosis', entry.diagnosis.join(', ')),
          if (entry.generalAdvice.isNotEmpty) _kv(scheme, 'Advice', entry.generalAdvice),
          if (entry.followUpOn != null) _kv(scheme, 'Follow-up', DateFormat('d MMM yyyy').format(entry.followUpOn!)),
          if (entry.doctorName != null) _kv(scheme, 'By', entry.doctorName!),
        ],
      ),
    );
  }

  Widget _kv(ColorScheme scheme, String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(v, style: const TextStyle(fontSize: 14, height: 1.35)),
          ],
        ),
      );
}

/// The reports the patient actually uploaded, each with its transcribed values,
/// a red at-a-glance line for anything out of range, and the file to open.
class _LabReportsSection extends StatelessWidget {
  const _LabReportsSection({required this.reports});

  final List<LabReport> reports;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final r in reports)
          Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _DietLabReportRow(report: r)),
      ],
    );
  }
}

/// Mirrors the doctor's lab-report row so "out of range" and "open PDF" read
/// identically in both panels. A photo opens full-screen; a PDF/document is
/// downloaded with the auth header (an in-browser open would 403) and handed to
/// the phone's viewer.
class _DietLabReportRow extends ConsumerStatefulWidget {
  const _DietLabReportRow({required this.report});

  final LabReport report;

  @override
  ConsumerState<_DietLabReportRow> createState() => _DietLabReportRowState();
}

class _DietLabReportRowState extends ConsumerState<_DietLabReportRow> {
  bool _busy = false;

  LabReport get report => widget.report;

  IconData _fileIcon() {
    final m = report.mimeType ?? '';
    if (m == 'application/pdf') return Icons.picture_as_pdf_rounded;
    if (m.startsWith('image/')) return Icons.image_rounded;
    return Icons.description_rounded;
  }

  Future<void> _open() async {
    if (!report.hasFile || report.photoUrl == null) return;
    if (report.isImage) {
      FullscreenPhoto.show(context, report.photoUrl);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await getTemporaryDirectory();
      final ext = report.mimeType == 'application/pdf' ? 'pdf' : 'bin';
      final cached = File('${dir.path}/lab_${report.photoUrl.hashCode}.$ext');
      if (!await cached.exists() || await cached.length() == 0) {
        final bytes = await ref.read(apiClientProvider).getBytes('${AppConfig.apiOrigin}${report.photoUrl}');
        if (bytes.isEmpty) throw Exception('empty report download');
        await cached.writeAsBytes(bytes, flush: true);
      }
      final res = await OpenFilex.open(cached.path);
      if (res.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app on this phone can open that report')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the report')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showThumb = report.hasFile && report.isImage;
    final abnormal = report.analytes.where((a) => a.abnormal).toList();

    final tile = Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: showThumb
                ? AuthedImage(path: report.photoUrl!, width: 52, height: 52, radius: 10)
                : Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(10)),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                        : Icon(_fileIcon(), color: scheme.onSurfaceVariant, size: 24),
                  ),
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
                if (report.analysisSummary != null && report.analysisSummary!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(report.analysisSummary!, style: const TextStyle(fontSize: 13, height: 1.3)),
                ] else if (report.note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(report.note, style: const TextStyle(fontSize: 13)),
                ],
                if (report.hasFile) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(showThumb ? Icons.visibility_outlined : Icons.open_in_new_rounded, size: 13, color: AppColors.accentOn(context)),
                      const SizedBox(width: 4),
                      Text(
                        showThumb ? 'Tap to view' : (report.mimeType == 'application/pdf' ? 'Tap to open PDF' : 'Tap to open'),
                        style: TextStyle(fontSize: 11.5, color: AppColors.accentOn(context), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
                if (abnormal.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.dangerOn(context)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Out of range: ${abnormal.map((a) => '${a.label} ${a.flag == 'low' ? '↓' : '↑'}').join(', ')}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.dangerOn(context)),
                        ),
                      ),
                    ],
                  ),
                ],
                if (report.analytes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final a in report.analytes) _AnalyteChip(analyte: a)]),
                ] else if (report.analysisStatus == 'failed' || report.analysisStatus == 'unsupported') ...[
                  const SizedBox(height: 6),
                  Text('Could not read automatically — needs a look',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.warningOn(context))),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (!report.hasFile) return tile;
    return InkWell(borderRadius: BorderRadius.circular(14), onTap: _open, child: tile);
  }
}

/// One transcribed value: "HbA1c 9.9 %" with a coloured border + arrow when it
/// is out of its reference range. Mirrors the doctor's chip.
class _AnalyteChip extends StatelessWidget {
  const _AnalyteChip({required this.analyte});

  final Analyte analyte;

  static String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final abnormal = analyte.abnormal;
    final color = switch (analyte.flag) {
      'high' || 'critical' => AppColors.dangerOn(context),
      'low' => AppColors.warningOn(context),
      _ => AppColors.successOn(context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: abnormal ? color.withValues(alpha: 0.12) : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: abnormal ? color.withValues(alpha: 0.4) : scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${analyte.label} ', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          Text(_fmt(analyte.value), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: abnormal ? color : scheme.onSurface)),
          if (analyte.unit != null && analyte.unit!.isNotEmpty)
            Text(' ${analyte.unit}', style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
          if (abnormal) ...[
            const SizedBox(width: 3),
            Icon(analyte.flag == 'low' ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded, size: 12, color: color),
          ],
        ],
      ),
    );
  }
}

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

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final o = overview;
    final risk = AppColors.toneOn(context, dietRiskColor(o.riskBand));
    final danger = AppColors.dangerOn(context);

    // No card around this one. It is the patient's identity, not a section of
    // their record — boxing it made the screen open with a panel and then a
    // stack of panels, with nothing saying which one was the person.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                o.name,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.15),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: risk.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_cap(o.riskBand)} Risk',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: risk),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Age, sex and height on one line with their marks. These three are
        // read together — they are what a calorie target is built from — so
        // they belong on one line rather than as three labelled cells.
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            if (o.age != null) _bit(context, Icons.calendar_today_rounded, '${o.age} yrs'),
            if ((o.gender ?? '').isNotEmpty) _bit(context, Icons.person_outline_rounded, _cap(o.gender!)),
            if (o.heightCm != null) _bit(context, Icons.height_rounded, '${o.heightCm} cm'),
            if (o.diabetesType != null && o.diabetesType!.isNotEmpty)
              _bit(context, Icons.monitor_heart_outlined, o.diabetesType!),
          ],
        ),

        if (o.chiefComplaint != null) ...[
          const SizedBox(height: AppSpacing.md),
          _label(context, 'MAIN CONCERN'),
          const SizedBox(height: 4),
          Text(o.chiefComplaint!, style: const TextStyle(fontSize: 14.5, height: 1.4)),
        ],

        if (o.allergies.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _label(context, 'ALLERGIES'),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final a in o.allergies)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    // Outlined rather than filled: an allergy is a hard stop
                    // when writing a meal plan, and an outline holds the eye
                    // where a soft wash blends into the page.
                    border: Border.all(color: danger.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    a,
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: danger),
                  ),
                ),
            ],
          ),
        ],

        const SizedBox(height: AppSpacing.md),
        Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ],
    );
  }

  Widget _bit(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _label(BuildContext context, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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

/// What the patient has eaten — the last day at a glance, then the history.
///
/// The day is drawn as the four meal slots rather than as a list of whatever
/// happened to be logged, because the useful question is usually the negative
/// one: which meal is missing. A list of three photographs cannot answer that;
/// a grid with an empty dinner slot answers it without being read.
class _FoodLogSection extends ConsumerWidget {
  const _FoodLogSection({required this.patientId});

  final String patientId;

  static const _slots = <String>['breakfast', 'lunch', 'snack', 'dinner'];

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Entries under a heading per day, newest day first, order preserved within
  /// each day.
  static Map<String, List<FoodLogEntry>> _byDay(List<FoodLogEntry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = <String, List<FoodLogEntry>>{};
    for (final e in entries) {
      final at = e.createdAt;
      final String key;
      if (at == null) {
        key = 'UNDATED';
      } else {
        final diff = today.difference(DateTime(at.year, at.month, at.day)).inDays;
        key = switch (diff) {
          0 => 'TODAY',
          1 => 'YESTERDAY',
          _ => DateFormat('EEEE, d MMMM').format(at).toUpperCase(),
        };
      }
      out.putIfAbsent(key, () => []).add(e);
    }
    return out;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietFoodLogProvider(patientId));

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _note(scheme, 'Could not load the food log.'),
      data: (entries) {
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        final recent = entries.where((e) => e.createdAt != null && e.createdAt!.isAfter(cutoff)).toList();
        final earlier = entries.where((e) => e.createdAt == null || !e.createdAt!.isAfter(cutoff)).toList();

        // The newest entry for each slot, so a patient who logged lunch twice
        // shows the one they most recently sent.
        final bySlot = <String, FoodLogEntry>{};
        for (final e in recent) {
          final key = _slots.contains(e.mealType) ? e.mealType : 'snack';
          bySlot.putIfAbsent(key, () => e);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.photo_camera_rounded, size: 19, color: AppColors.accentOn(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Food Log (Last 24h)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentOn(context),
                          ),
                        ),
                      ),
                      if (entries.isNotEmpty)
                        Text(
                          '${recent.length} logged',
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (var row = 0; row < _slots.length; row += 2) ...[
                    if (row > 0) const SizedBox(height: AppSpacing.sm),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _SlotTile(slot: _slots[row], entry: bySlot[_slots[row]])),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: _SlotTile(slot: _slots[row + 1], entry: bySlot[_slots[row + 1]])),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (earlier.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history_rounded, size: 19, color: AppColors.accentOn(context)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Earlier Meals',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.accentOn(context),
                            ),
                          ),
                        ),
                        Text(
                          '${earlier.length} logged',
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    // Grouped by the day they were eaten. A flat run of thirty
                    // meals gives no sense of whether the patient logged three
                    // days solidly or one day nine times.
                    for (final day in _byDay(earlier.take(30).toList()).entries) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        day.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      for (var i = 0; i < day.value.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        _FoodEntry(entry: day.value[i]),
                      ],
                    ],
                  ],
                ),
              ),
            ],
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

/// One meal slot in the day: the photograph if it was logged, a dashed outline
/// saying which meal is missing if it was not.
class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.entry});

  final String slot;
  final FoodLogEntry? entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _FoodLogSection._cap(slot);
    final e = entry;

    if (e == null) {
      return AspectRatio(
        aspectRatio: 1.05,
        child: DottedBorderBox(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.help_outline_rounded, size: 19, color: scheme.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(
                'No $slot logged',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: e.photoUrl == null ? null : () => FullscreenPhoto.show(context, e.photoUrl),
        child: AspectRatio(
          aspectRatio: 1.05,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (e.photoUrl != null)
                AuthedImage(path: e.photoUrl!, fit: BoxFit.cover)
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: Text(
                      e.note.isEmpty ? label : e.note,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 7),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0B1B33).withValues(alpha: 0),
                        const Color(0xFF0B1B33).withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      if (e.createdAt != null) ...[
                        Text(
                          DateFormat('h:mm a').format(e.createdAt!),
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed placeholder. Flutter has no dashed border, so this paints one.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashPainter(Theme.of(context).colorScheme.outlineVariant),
      child: Center(child: child),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.65, 0.65, size.width - 1.3, size.height - 1.3),
      const Radius.circular(10),
    );

    // Walk the rounded rectangle and draw every other short run of it.
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final end = (d + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.colour != colour;
}

class _FoodEntry extends StatelessWidget {
  const _FoodEntry({required this.entry});

  final FoodLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meal = entry.mealType.isEmpty ? 'Meal' : '${entry.mealType[0].toUpperCase()}${entry.mealType.substring(1)}';
    // Sits inside the Earlier Meals card now, so it drops its own border and
    // takes a soft fill instead — a bordered box inside a bordered box read as
    // two frames around one meal.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.photoUrl != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: AuthedImage(path: entry.photoUrl!, width: 52, height: 52, radius: 10),
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
                      Text(DateFormat('h:mm a').format(entry.createdAt!), style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
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
        _MeasureTile(label: 'Blood pressure', value: v.bloodPressure!.label, unit: 'mmHg', at: v.bloodPressure!.at, danger: v.bloodPressure!.isHigh, trend: v.bloodPressure!.trend),
      if (v.glucose != null)
        _MeasureTile(label: _glucoseLabel(v.glucose!.context), value: _n(v.glucose!.valueMgDl), unit: 'mg/dL', at: v.glucose!.at, danger: v.glucose!.isAbnormal),
      if (v.weightKg != null) _MeasureTile(label: 'Weight', value: _n(v.weightKg!.value), unit: 'kg', at: v.weightKg!.at, trend: v.weightKg!.trend),
      if (v.bmi != null) _MeasureTile(label: 'BMI', value: _n(v.bmi!), unit: '', at: null),
      if (v.waistCm != null) _MeasureTile(label: 'Waist', value: _n(v.waistCm!.value), unit: 'cm', at: v.waistCm!.at, trend: v.waistCm!.trend),
      if (v.pulse != null) _MeasureTile(label: 'Pulse', value: _n(v.pulse!.value), unit: 'bpm', at: v.pulse!.at, trend: v.pulse!.trend),
      if (v.spo2 != null) _MeasureTile(label: 'SpO₂', value: _n(v.spo2!.value), unit: '%', at: v.spo2!.at, trend: v.spo2!.trend),
      if (v.temperatureC != null) _MeasureTile(label: 'Temp', value: _n(v.temperatureC!.value), unit: '°C', at: v.temperatureC!.at, trend: v.temperatureC!.trend),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B33).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      // A single column with rules between, not a two-across grid. Each row
      // carries a trend arrow on its right edge, and paired into columns those
      // arrows landed mid-card where they read as decoration rather than as the
      // end of a line.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_rounded, size: 19, color: AppColors.accentOn(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recent Vitals',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentOn(context),
                  ),
                ),
              ),
              Text(
                tiles.length == 1 ? '1 measure' : '${tiles.length} measures',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (var i = 0; i < tiles.length; i++) ...[
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            tiles[i],
          ],
        ],
      ),
    );
  }
}

/// One measurement: what it is, what it read, and which way it is moving.
///
/// The arrow is drawn only when the record actually holds an earlier reading to
/// compare against. It says direction, not judgement — whether a falling weight
/// is good or bad depends on the patient, and that is the dietician's call.
class _MeasureTile extends StatelessWidget {
  const _MeasureTile({
    required this.label,
    required this.value,
    required this.unit,
    required this.at,
    this.danger = false,
    this.trend,
  });

  final String label;
  final String value;
  final String unit;
  final DateTime? at;
  final bool danger;
  final int? trend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? AppColors.dangerOn(context) : scheme.onSurface;

    final (IconData icon, Color colour)? arrow = switch (trend) {
      1 => (Icons.trending_up_rounded, AppColors.dangerOn(context)),
      -1 => (Icons.trending_down_rounded, scheme.onSurfaceVariant),
      0 => (Icons.trending_flat_rounded, AppColors.accentOn(context)),
      _ => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: fg),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                    if (at != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('d MMM').format(at!),
                        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (arrow != null) Icon(arrow.$1, size: 20, color: arrow.$2),
        ],
      ),
    );
  }
}

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

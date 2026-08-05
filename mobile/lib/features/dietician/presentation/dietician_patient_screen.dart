import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/authed_image.dart';
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
    final risk = dietRiskColor(o.riskBand);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
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
              if (o.gender != null && o.gender!.isNotEmpty) _fact('Gender', o.gender!, scheme),
              if (o.heightCm != null) _fact('Height', '${o.heightCm} cm', scheme),
              if (o.reviewIntervalDays != null) _fact('Review every', '${o.reviewIntervalDays} days', scheme),
            ],
          ),
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
                    decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                    child: Text(a, style: const TextStyle(fontSize: 12.5, color: AppColors.danger, fontWeight: FontWeight.w600)),
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
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.medication_rounded, size: 18, color: AppColors.primary),
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
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            meal.time.isNotEmpty ? '${meal.name} · ${meal.time}' : meal.name,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      if (plan.avoid.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${plan.avoid.length} to avoid',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.danger,
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
                    Text(meal, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
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

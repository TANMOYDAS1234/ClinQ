import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/diet_models.dart';
import 'dietician_patients_screen.dart' show dietRiskColor;
import 'dietician_providers.dart';

/// The dietician's day in one screen.
///
/// Ordered by what is actionable, not by what is impressive: reviews that are
/// overdue first, then patients still waiting for a plan, then the food logs
/// that came in while they were away. Counts and lists come from one endpoint
/// so a number never disagrees with the list under it.
class DieticianDashboardScreen extends ConsumerWidget {
  const DieticianDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    final async = ref.watch(dietDashboardProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dashboard',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
            Text(
              'Dietician · ${user?.name ?? ''}',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(dietDashboardProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 140),
              const Center(child: Text('Could not load your dashboard')),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(dietDashboardProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          data: (d) => ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
            children: [
              Row(
                children: [
                  Expanded(child: _Stat(value: '${d.patients}', label: 'My\npatients', color: AppColors.primary)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Stat(
                      value: '${d.reviewsDue}',
                      label: 'Reviews\ndue',
                      color: d.reviewsDue > 0 ? AppColors.warning : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _Stat(
                      value: '${d.plansMissing}',
                      label: 'Plans to\nsend',
                      color: d.plansMissing > 0 ? const Color(0xFFEA580C) : AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              if (d.reviewsDueList.isNotEmpty) ...[
                const _SectionTitle('Reviews due'),
                for (final p in d.reviewsDueList)
                  _PatientRow(
                    patient: p,
                    trailing: _Badge(
                      _sinceLabel(p.lastReviewAt),
                      const Color(0xFFB45309),
                      AppColors.warning,
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],

              if (d.plansMissingList.isNotEmpty) ...[
                const _SectionTitle('Waiting for a diet plan'),
                for (final p in d.plansMissingList)
                  _PatientRow(
                    patient: p,
                    trailing: const _Badge('No plan sent', Color(0xFFC2410C), Color(0xFFEA580C)),
                  ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // Only claim "all caught up" when both worklists are genuinely
              // empty — a green tick over outstanding work is worse than none.
              if (d.reviewsDueList.isEmpty && d.plansMissingList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 30),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'All caught up',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.patients == 0
                                  ? 'A doctor will assign patients to you.'
                                  : 'Every plan is sent and no review is due.',
                              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              if (d.recentLogs.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const _SectionTitle('Latest meals logged'),
                for (final log in d.recentLogs) _LogRow(log: log),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _sinceLabel(DateTime? last) {
    if (last == null) return 'Never reviewed';
    final days = DateTime.now().difference(last).inDays;
    if (days <= 0) return 'Today';
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color, height: 1.1)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.25, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.fg, this.bg);

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.patient, required this.trailing});

  final DietPatientBrief patient;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final risk = dietRiskColor(patient.riskBand);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/dietician/patients/${patient.id}', extra: patient.name),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                UserAvatar(name: patient.name, avatarUrl: null, accent: risk, size: 42),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        patient.diabetesType?.isNotEmpty == true
                            ? patient.diabetesType!
                            : '${patient.riskBand[0].toUpperCase()}${patient.riskBand.substring(1)} risk',
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.log});

  final DietRecentLog log;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final when = log.createdAt;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/dietician/patients/${log.patientId}', extra: log.patientName),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: log.photoUrl != null
                      ? Image.network(
                          '${AppConfig.apiOrigin}${log.photoUrl}',
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(scheme),
                        )
                      : _placeholder(scheme),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        log.note.isNotEmpty ? log.note : log.mealType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (when != null)
                  Text(
                    DateFormat('d MMM, h:mm a').format(when),
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) => Container(
    width: 52,
    height: 52,
    color: scheme.surfaceContainerHighest,
    child: Icon(Icons.restaurant_menu_rounded, size: 22, color: scheme.onSurfaceVariant),
  );
}

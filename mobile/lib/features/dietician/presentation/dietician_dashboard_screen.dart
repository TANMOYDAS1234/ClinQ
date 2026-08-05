import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/diet_models.dart';
import 'dietician_providers.dart';

/// The dietician's day in one screen.
///
/// Ordered by what is actionable rather than what looks impressive: the counts,
/// then the queue of work outstanding, then what came in while they were away.
/// Counts and lists come from one endpoint, so a number never disagrees with
/// the list under it.
class DieticianDashboardScreen extends ConsumerWidget {
  const DieticianDashboardScreen({super.key});

  static String _partOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    final async = ref.watch(dietDashboardProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _BrandHeader(user: user),
            Expanded(
              child: RefreshIndicator(
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
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    children: [
                      Text(
                        '${_partOfDay()}, ${user?.name ?? ''}',
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.5,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Here is your daily nutrition overview.',
                        style: TextStyle(fontSize: 15.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      _StatTrio(dashboard: d),
                      const SizedBox(height: AppSpacing.md),

                      if (d.queue.isNotEmpty) ...[
                        _ActionQueue(items: d.queue, pending: d.reviewsDue + d.plansMissing),
                        const SizedBox(height: AppSpacing.lg),
                      ] else ...[
                        _AllCaught(patients: d.patients),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      if (d.recentLogs.isNotEmpty) _LatestMeals(meals: d.recentLogs),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Header ---------------------------------------------------------------

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.user});

  final dynamic user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/brand/logo_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.restaurant_rounded, size: 26, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const Spacer(),
          UserAvatar(
            name: user?.name ?? '',
            avatarUrl: user?.avatarUrl,
            accent: AppColors.primary,
            size: 38,
          ),
        ],
      ),
    );
  }
}

// ---- Counts ---------------------------------------------------------------

class _StatTrio extends StatelessWidget {
  const _StatTrio({required this.dashboard});

  final DietDashboard dashboard;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight, not a bare stretch: inside a ListView the cross-axis is
    // unbounded, and stretching would make the boxes infinitely tall.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _StatBox(label: 'Patients', value: dashboard.patients)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatBox(
              label: 'Reviews',
              value: dashboard.reviewsDue,
              // Tinted only when there is something to do. A permanently red
              // box stops meaning anything.
              accent: dashboard.reviewsDue > 0 ? AppColors.danger : null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _StatBox(
              label: 'Plans',
              value: dashboard.plansMissing,
              accent: dashboard.plansMissing > 0 ? AppColors.primary : null,
              tint: AppColors.infoBg,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.label, required this.value, this.accent, this.tint});

  final String label;
  final int value;
  final Color? accent;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = accent ?? scheme.outlineVariant;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.surfaceContainerLowest
            : (tint ?? accent!.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border.withValues(alpha: accent == null ? 0.7 : 0.45)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: accent ?? scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Action queue ---------------------------------------------------------

class _ActionQueue extends StatelessWidget {
  const _ActionQueue({required this.items, required this.pending});

  final List<DietQueueItem> items;
  final int pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.assignment_outlined, size: 21, color: scheme.onSurface),
                const SizedBox(width: AppSpacing.sm),
                const Text('Action Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(
                  '$pending Pending',
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          for (final item in items) ...[
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            _QueueRow(item: item),
          ],
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.item});

  final DietQueueItem item;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsPlan = item.needsPlan;

    return InkWell(
      onTap: () => context.push('/dietician/patients/${item.patientId}', extra: item.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: needsPlan ? AppColors.infoBg : AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                _initials(item.name),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${needsPlan ? 'Create Plan' : 'Review Due'} · ${item.label}',
                    style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (needsPlan)
              Material(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () =>
                      context.push('/dietician/patients/${item.patientId}/diet', extra: item.name),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    child: Text(
                      'Create',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              )
            else
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Shown only when both worklists are genuinely empty — a green tick over
/// outstanding work is worse than no tick.
class _AllCaught extends StatelessWidget {
  const _AllCaught({required this.patients});

  final int patients;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
                  patients == 0
                      ? 'No patients on the clinic list yet.'
                      : 'Every plan is sent and no review is due.',
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Latest meals ---------------------------------------------------------

class _LatestMeals extends StatelessWidget {
  const _LatestMeals({required this.meals});

  final List<DietRecentLog> meals;

  static String _ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  static String _label(String mealType) =>
      mealType.isEmpty ? '' : mealType[0].toUpperCase() + mealType.substring(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.restaurant_rounded, size: 21, color: scheme.onSurface),
            const SizedBox(width: AppSpacing.sm),
            const Text('Latest Meals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: meals.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final meal = meals[i];
              return SizedBox(
                width: 190,
                child: Material(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => context.push(
                      '/dietician/patients/${meal.patientId}',
                      extra: meal.patientName,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              SizedBox(
                                height: 118,
                                width: double.infinity,
                                child: meal.photoUrl != null
                                    ? AuthedImage(path: meal.photoUrl!, fit: BoxFit.cover)
                                    : Container(
                                        color: scheme.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.restaurant_menu_rounded,
                                          size: 30,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                              ),
                              if (meal.mealType.isNotEmpty)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      _label(meal.mealType),
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meal.patientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _ago(meal.createdAt),
                                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

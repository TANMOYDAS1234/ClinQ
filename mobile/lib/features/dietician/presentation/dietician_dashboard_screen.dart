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
/// Ordered by what is actionable rather than what is impressive: the counts,
/// then reviews that have lapsed, then patients still waiting for a plan, then
/// what came in while they were away. Counts and lists come from one endpoint,
/// so a number never disagrees with the list under it.
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
            _BrandHeader(name: user?.name ?? '', avatarUrl: user?.avatarUrl),
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
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Here is your daily clinical overview.',
                        style: TextStyle(fontSize: 15.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      _StatCard(
                        label: 'My Patients',
                        value: '${d.patients}',
                        // Only when someone actually joined — "+0 this week" is
                        // noise dressed as news.
                        note: d.newThisWeek > 0 ? '+${d.newThisWeek} this week' : null,
                        noteColor: AppColors.primary,
                        icon: Icons.groups_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _StatCard(
                        label: 'Reviews Due',
                        value: '${d.reviewsDue}',
                        note: d.reviewsDue > 0 ? 'require immediate action' : 'nothing overdue',
                        // Tinted only when there is something to do. A
                        // permanently red card stops meaning anything.
                        accent: d.reviewsDue > 0 ? AppColors.danger : null,
                        icon: Icons.notifications_active_outlined,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _StatCard(
                        label: 'Plans to Send',
                        value: '${d.plansMissing}',
                        note: d.plansMissing > 0 ? 'waiting on you' : 'all sent',
                        accent: d.plansMissing > 0 ? AppColors.primary : null,
                        tint: AppColors.infoBgOn(context),
                        icon: Icons.assignment_outlined,
                      ),

                      if (d.reviewsSorted.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _WorkCard(
                          icon: Icons.warning_amber_rounded,
                          iconColor: AppColors.danger,
                          title: 'Reviews Due',
                          action: d.reviewsSorted.length > 3 ? 'View All' : null,
                          onAction: () => context.go('/dietician/patients'),
                          children: [
                            for (final p in d.reviewsSorted.take(3))
                              _PatientRow(
                                patient: p,
                                subtitle: _condition(p),
                                trailing: _AgePill(days: p.sinceDays),
                                onTap: () => context.push(
                                  '/dietician/patients/${p.id}',
                                  extra: p.name,
                                ),
                              ),
                          ],
                        ),
                      ],

                      if (d.plansSorted.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _WorkCard(
                          icon: Icons.event_note_outlined,
                          iconColor: AppColors.primary,
                          title: 'Waiting for Diet Plan',
                          children: [
                            for (final p in d.plansSorted.take(3))
                              _PatientRow(
                                patient: p,
                                subtitle: p.sinceDays == 0
                                    ? 'Joined today'
                                    : 'Waiting ${p.sinceDays} ${p.sinceDays == 1 ? 'day' : 'days'}',
                                trailing: _CreateButton(
                                  onTap: () => context.push(
                                    '/dietician/patients/${p.id}/diet',
                                    extra: p.name,
                                  ),
                                ),
                                onTap: () => context.push(
                                  '/dietician/patients/${p.id}',
                                  extra: p.name,
                                ),
                              ),
                          ],
                        ),
                      ],

                      if (d.reviewsSorted.isEmpty && d.plansSorted.isEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _AllCaught(patients: d.patients),
                      ],

                      if (d.recentLogs.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            Icon(Icons.restaurant_rounded, size: 21, color: scheme.onSurface),
                            const SizedBox(width: AppSpacing.sm),
                            const Text(
                              'Latest Meals Logged',
                              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        for (final log in d.recentLogs.take(6)) _MealCard(log: log),
                      ],
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

  static String _condition(DietPatientBrief p) => switch (p.diabetesType) {
    'type1' => 'Type 1 Diabetes',
    'type2' => 'Type 2 Diabetes',
    'gestational' => 'Gestational Diabetes',
    'prediabetes' => 'Prediabetes',
    _ => '${p.riskBand[0].toUpperCase()}${p.riskBand.substring(1)} risk',
  };
}

// ---- Header ---------------------------------------------------------------

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

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
                Icon(Icons.restaurant_rounded, size: 26, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 10),
          Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/dietician/profile'),
            child: UserAvatar(name: name, avatarUrl: avatarUrl, accent: AppColors.accentOn(context), size: 38),
          ),
        ],
      ),
    );
  }
}

// ---- Counts ---------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.note,
    this.noteColor,
    this.accent,
    this.tint,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? note;
  final Color? noteColor;
  final Color? accent;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent == null
            ? scheme.surfaceContainerLowest
            : (tint ?? accent!.withValues(alpha: 0.06)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (accent ?? scheme.outlineVariant).withValues(alpha: accent == null ? 0.7 : 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
                ),
              ),
              Icon(icon, size: 21, color: accent ?? scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: accent ?? scheme.onSurface,
                ),
              ),
              if (note != null) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: noteColor ?? accent ?? scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Worklists ------------------------------------------------------------

class _WorkCard extends StatelessWidget {
  const _WorkCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.children,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final List<Widget> children;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              children: [
                Icon(icon, size: 21, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                ),
                if (action != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(
                      action!,
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentOn(context)),
                    ),
                  ),
              ],
            ),
          ),
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({
    required this.patient,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final DietPatientBrief patient;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.accentSoftOn(context), shape: BoxShape.circle),
              child: Text(
                _initials(patient.name),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentOn(context),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _AgePill extends StatelessWidget {
  const _AgePill({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.dangerBgOn(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            days == 0 ? 'today' : '$days ${days == 1 ? 'day' : 'days'} ago',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.dangerOn(context),
            ),
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
      ],
    );
  }
}

class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.accentSoftOn(context),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Create Plan',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.accentOn(context)),
          ),
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
        color: AppColors.accentSoftOn(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AppColors.accentOn(context), size: 30),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'All caught up',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
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

// ---- Meals ----------------------------------------------------------------

class _MealCard extends StatelessWidget {
  const _MealCard({required this.log});

  final DietRecentLog log;

  static String _ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return 'Logged ${d.inMinutes} minutes ago';
    if (d.inHours < 24) return 'Logged ${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
    return 'Logged ${d.inDays} ${d.inDays == 1 ? 'day' : 'days'} ago';
  }

  static String _label(String mealType) =>
      mealType.isEmpty ? '' : mealType[0].toUpperCase() + mealType.substring(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/dietician/patients/${log.patientId}', extra: log.patientName),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: log.photoUrl != null
                          ? AuthedImage(path: log.photoUrl!, fit: BoxFit.cover)
                          : Container(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.restaurant_menu_rounded,
                                size: 34,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    if (log.mealType.isNotEmpty)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _label(log.mealType),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.patientName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _ago(log.createdAt),
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
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
  }
}

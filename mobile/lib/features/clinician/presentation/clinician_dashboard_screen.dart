import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../domain/appointment.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';

/// The doctor's home: clinic pulse at a glance — headline counts, the alerts
/// that need attention, and today's schedule. Every number is live: pulled from
/// the API and refreshed on a timer, on resume, and on pull-to-refresh, so it is
/// never stale while the doctor is looking at it.
class ClinicianDashboardScreen extends ConsumerStatefulWidget {
  const ClinicianDashboardScreen({super.key});

  @override
  ConsumerState<ClinicianDashboardScreen> createState() => _ClinicianDashboardScreenState();
}

class _ClinicianDashboardScreenState extends ConsumerState<ClinicianDashboardScreen>
    with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Live updates: re-pull the counts and the diary every 20s so a new message,
    // a resolved alert or a checked-in patient shows without any manual refresh.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    ref.invalidate(overviewProvider);
    ref.invalidate(appointmentsTodayProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // valueOrNull, not .when: on a timer refresh the provider briefly re-enters
    // loading, and reading the last value keeps the screen from flashing a
    // spinner every 20 seconds.
    final overview = ref.watch(overviewProvider).valueOrNull;
    final appts = ref.watch(appointmentsTodayProvider).valueOrNull;
    final loading = overview == null && ref.watch(overviewProvider).isLoading;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _DashboardHeader(),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () async => _refresh(),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
                        children: [
                          if (overview != null)
                            _StatsRow(
                              overview: overview,
                              // Count completed from the same list the schedule
                              // shows, so the headline and the diary always agree
                              // (and it works before the backend redeploy too).
                              completed: appts != null
                                  ? appts.where((a) => a.isCompleted).length
                                  : overview.completedToday,
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          if (overview != null) _ActiveAlerts(overview: overview),
                          const SizedBox(height: AppSpacing.lg),
                          _ScheduleSection(appointments: appts ?? const []),
                        ],
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

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          Image.asset(
            'assets/brand/logo_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) => const Icon(Icons.forum_rounded, size: 26, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Search patients',
            onPressed: () => context.go('/clinician/patients'),
            icon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: () => context.go('/clinician/more'),
            child: UserAvatar(
              name: user?.name ?? 'Dr',
              avatarUrl: user?.avatarUrl,
              accent: AppColors.primary,
              size: 40,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Headline stats -------------------------------------------------------

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.overview, required this.completed});

  final ClinicOverview overview;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              value: overview.patientCount,
              label: 'Total\nPatients',
              icon: Icons.groups_rounded,
              onTap: () => context.go('/clinician/patients'),
            ),
          ),
          _divider(scheme),
          Expanded(
            child: _Stat(
              value: overview.pendingReviews,
              label: 'Pending\nSummaries',
              icon: Icons.pending_actions_rounded,
              onTap: () => context.push('/clinician/chat-review'),
            ),
          ),
          _divider(scheme),
          Expanded(
            child: _Stat(
              value: completed,
              label: 'Completed',
              icon: Icons.check_circle_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) =>
      Container(width: 1, height: 44, color: scheme.outlineVariant.withValues(alpha: 0.7));
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.icon, this.onTap});

  final int value;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: Column(
          children: [
            Text(
              '$value',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.15, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Active alerts --------------------------------------------------------

class _ActiveAlerts extends StatelessWidget {
  const _ActiveAlerts({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pills = <Widget>[
      if (overview.highPriorityAlerts > 0)
        _AlertPill(
          label: 'High Priority',
          count: overview.highPriorityAlerts,
          fg: AppColors.danger,
          bg: AppColors.dangerBg,
          icon: Icons.priority_high_rounded,
          onTap: () => context.push('/clinician/alerts'),
        ),
      if (overview.unreadMessages > 0)
        _AlertPill(
          label: 'New Messages',
          count: overview.unreadMessages,
          fg: AppColors.primary,
          bg: AppColors.accentSoft,
          icon: Icons.mark_email_unread_rounded,
          onTap: () => context.go('/clinician/patients'),
        ),
      if (overview.warningAlerts > 0)
        _AlertPill(
          label: 'Vitals Warning',
          count: overview.warningAlerts,
          fg: const Color(0xFF4338CA),
          bg: const Color(0xFFE0E7FF),
          icon: Icons.monitor_heart_rounded,
          onTap: () => context.push('/clinician/alerts'),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Active Alerts'),
        const SizedBox(height: AppSpacing.sm),
        if (pills.isEmpty)
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.success),
              const SizedBox(width: 8),
              Text('No active alerts right now', style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant)),
            ],
          )
        else
          Wrap(spacing: 10, runSpacing: 10, children: pills),
      ],
    );
  }
}

class _AlertPill extends StatelessWidget {
  const _AlertPill({
    required this.label,
    required this.count,
    required this.fg,
    required this.bg,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color fg;
  final Color bg;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: fg),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
              const SizedBox(width: 7),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(10)),
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Daily schedule -------------------------------------------------------

class _ScheduleSection extends StatelessWidget {
  const _ScheduleSection({required this.appointments});

  final List<Appointment> appointments;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            const _SectionTitle('Daily Schedule'),
            const Spacer(),
            InkWell(
              onTap: () => context.push('/clinician/appointments'),
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'View Full Calendar',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (appointments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Icon(Icons.event_available_rounded, size: 34, color: scheme.onSurfaceVariant),
                const SizedBox(height: 10),
                Text('No appointments scheduled today',
                    style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          )
        else
          for (var i = 0; i < appointments.length; i++)
            _ScheduleRow(
              appt: appointments[i],
              isFirst: i == 0,
              isLast: i == appointments.length - 1,
            ),
      ],
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.appt, required this.isFirst, required this.isLast});

  final Appointment appt;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = scheme.outlineVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail: a dot on a connecting line.
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Expanded(child: Container(width: 2, color: isFirst ? Colors.transparent : line)),
                _dot(),
                Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : line)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: appt.isInProgress ? _activeCard(context, scheme) : _plainItem(context, scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() {
    if (appt.isInProgress) {
      return Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accentSoft, width: 3),
        ),
      );
    }
    final color = appt.isCompleted ? AppColors.accent.withValues(alpha: 0.55) : AppColors.primary;
    return Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }

  // The current patient — a filled card with the primary action.
  Widget _activeCard(BuildContext context, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_time(appt.scheduledFor),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              const _StatusChip(label: 'IN PROGRESS', fg: Colors.white, bg: AppColors.primary),
            ],
          ),
          const SizedBox(height: 8),
          Text(appt.patientName,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          if (appt.reason != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(appt.mode == 'teleconsult' ? Icons.videocam_rounded : Icons.science_outlined,
                    size: 15, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(appt.reason!,
                      style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  context.push('/clinician/patients/${appt.patientId}/thread', extra: appt.patientName),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              child: const Text('Open Chart', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // Completed or upcoming — a lighter row.
  Widget _plainItem(BuildContext context, ColorScheme scheme) {
    final done = appt.isCompleted;
    final muted = scheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _time(appt.scheduledFor),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: done ? muted : scheme.onSurface,
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
            const SizedBox(width: 10),
            if (done)
              _StatusChip(label: 'COMPLETED', fg: muted, bg: scheme.surfaceContainerHighest)
            else if (appt.isCancelled)
              const _StatusChip(label: 'CANCELLED', fg: AppColors.danger, bg: AppColors.dangerBg),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          appt.patientName,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: done ? muted : scheme.onSurface),
        ),
        if (appt.reason != null) ...[
          const SizedBox(height: 2),
          Text(appt.reason!, style: TextStyle(fontSize: 14, color: muted)),
        ],
        // "Prep" only for a visit still to come.
        if (appt.isUpcoming) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/clinician/patients/${appt.patientId}'),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                backgroundColor: AppColors.accentSoft.withValues(alpha: 0.5),
                side: BorderSide.none,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
              label: const Text('Prep', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ],
    );
  }

  static String _time(DateTime t) {
    final h = t.hour;
    final m = t.minute.toString().padLeft(2, '0');
    final period = h < 12 ? 'AM' : 'PM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.fg, required this.bg});

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.4),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800));
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';

/// The doctor's home: the clinic at a glance — headline counts, the alerts that
/// need attention, the clinic's risk pulse, and a ranked "needs attention"
/// worklist of the patients to deal with next. Every number is live: pulled from
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
    ref.invalidate(attentionPatientsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // valueOrNull, not .when: on a timer refresh the provider briefly re-enters
    // loading, and reading the last value keeps the screen from flashing a
    // spinner every 20 seconds.
    final overview = ref.watch(overviewProvider).valueOrNull;
    final patients = ref.watch(attentionPatientsProvider).valueOrNull;
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
                          if (overview != null) _StatsRow(overview: overview),
                          const SizedBox(height: AppSpacing.lg),
                          if (overview != null) _ActiveAlerts(overview: overview),
                          const SizedBox(height: AppSpacing.lg),
                          if (overview != null) _ClinicPulse(overview: overview),
                          const SizedBox(height: AppSpacing.lg),
                          if (overview != null) _NutritionCard(overview: overview),
                          const SizedBox(height: AppSpacing.lg),
                          _NeedsAttention(patients: patients ?? const []),
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
  const _StatsRow({required this.overview});

  final ClinicOverview overview;

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
              value: overview.activeToday,
              label: 'Active\nToday',
              icon: Icons.monitor_heart_rounded,
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

// ---- Clinic pulse ---------------------------------------------------------

/// One segment of the risk-distribution bar.
class _RiskSeg {
  const _RiskSeg(this.label, this.count, this.color);
  final String label;
  final int count;
  final Color color;
}

/// A premium at-a-glance strip: the clinic's risk profile as a segmented bar,
/// plus a couple of live activity numbers. All from the one overview call.
class _ClinicPulse extends StatelessWidget {
  const _ClinicPulse({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segs = <_RiskSeg>[
      _RiskSeg('Low', overview.riskLow, AppColors.success),
      _RiskSeg('Moderate', overview.riskModerate, AppColors.warning),
      _RiskSeg('High', overview.riskHigh, const Color(0xFFEA580C)),
      _RiskSeg('Critical', overview.riskCritical, AppColors.danger),
    ];
    final total = segs.fold<int>(0, (s, e) => s + e.count);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Clinic Pulse'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Patient risk profile',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 10,
                  child: total == 0
                      ? ColoredBox(color: scheme.surfaceContainerHighest)
                      : Row(
                          children: [
                            for (final s in segs)
                              if (s.count > 0) Expanded(flex: s.count, child: ColoredBox(color: s.color)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 11),
              Wrap(
                spacing: 14,
                runSpacing: 7,
                children: [for (final s in segs) _legend(s.color, s.label, s.count, scheme)],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
              ),
              Row(
                children: [
                  _pulseStat(Icons.monitor_heart_rounded, overview.activeToday, 'active today', scheme),
                  const SizedBox(width: 22),
                  _pulseStat(Icons.notifications_active_rounded, overview.totalOpenAlerts, 'open alerts', scheme),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legend(Color color, String label, int count, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label $count', style: TextStyle(fontSize: 12.5, color: scheme.onSurface)),
      ],
    );
  }

  Widget _pulseStat(IconData icon, int value, String label, ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 6),
        Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

// ---- Needs attention ------------------------------------------------------

/// One patient that needs the doctor now, with why and how urgent.
class _Attention {
  const _Attention(this.patient, this.tier, this.color, this.reason);
  final PatientListItem patient;
  final int tier; // 1 = most urgent
  final Color color;
  final String reason;
}

/// The doctor's worklist: patients ranked by how much they need attention right
/// now — abnormal glucose and emergencies first, then open alerts and urgent
/// messages, then high risk, then unanswered messages. Tap opens the thread.
class _NeedsAttention extends StatelessWidget {
  const _NeedsAttention({required this.patients});

  final List<PatientListItem> patients;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <_Attention>[];
    for (final p in patients) {
      final a = _attentionFor(p);
      if (a != null) items.add(a);
    }
    items.sort((a, b) => a.tier.compareTo(b.tier));
    final top = items.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle('Needs Attention'),
            const Spacer(),
            if (items.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(11)),
                child: Text(
                  '${items.length}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (top.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl, horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              children: [
                Icon(Icons.check_circle_rounded, size: 34, color: AppColors.success),
                const SizedBox(height: 10),
                const Text('All caught up', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  'No patients need attention right now',
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, indent: 60, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                  _AttentionRow(item: top[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }

  _Attention? _attentionFor(PatientListItem p) {
    final v = p.lastReadingValue;
    final urgency = p.lastMessage?.urgency;
    const orange = Color(0xFFEA580C);

    // Tier 1 — clinical red flags.
    if (v != null && (v >= 250 || v <= 70)) {
      return _Attention(p, 1, AppColors.danger, 'Glucose ${v.round()} mg/dL');
    }
    if (urgency == 'emergency') return _Attention(p, 1, AppColors.danger, 'Emergency flagged');

    // Tier 2 — needs review.
    if (p.openAlertCount > 0) {
      return _Attention(
          p, 2, orange, p.openAlertCount == 1 ? '1 open alert' : '${p.openAlertCount} open alerts');
    }
    if (urgency == 'urgent') return _Attention(p, 2, orange, 'Urgent message');
    if (p.riskBand == 'critical') return _Attention(p, 2, AppColors.danger, 'Critical risk');

    // Tier 3 — elevated risk.
    if (p.riskBand == 'high') return _Attention(p, 3, AppColors.warning, 'High risk');

    // Tier 4 — waiting for a reply.
    if (p.unreadCount > 0) {
      return _Attention(
          p, 4, AppColors.primary, p.unreadCount == 1 ? '1 new message' : '${p.unreadCount} new messages');
    }
    return null;
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final _Attention item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = item.patient;
    return InkWell(
      onTap: () => context.push('/clinician/patients/${p.id}/thread', extra: p.name),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: item.color),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: UserAvatar(name: p.name, avatarUrl: p.avatarUrl, accent: item.color, size: 42),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.reason,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: item.color),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
          ],
        ),
      ),
    );
  }
}

class _NutritionCard extends StatelessWidget {
  const _NutritionCard({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Nutrition'),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              _stat(Icons.restaurant_menu_rounded, overview.dietPatients, 'with dietician', scheme),
              const SizedBox(width: 22),
              _stat(Icons.photo_camera_back_outlined, overview.foodLogsToday, 'meals logged today', scheme),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(IconData icon, int value, String label, ColorScheme scheme) => Flexible(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('$value', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
            const SizedBox(width: 4),
            Flexible(child: Text(label, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant))),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800));
  }
}

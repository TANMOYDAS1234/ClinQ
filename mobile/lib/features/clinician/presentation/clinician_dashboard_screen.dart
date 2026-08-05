import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';

/// The doctor's home: the clinic at a glance — headline counts, what is on
/// today, the alerts that need attention, the live triage queue, and the
/// nutrition reviews coming due.
///
/// Every number is live: pulled from the API and refreshed on a timer, on
/// resume, and on pull-to-refresh, so it is never stale while the doctor is
/// looking at it.
class ClinicianDashboardScreen extends ConsumerStatefulWidget {
  const ClinicianDashboardScreen({super.key});

  @override
  ConsumerState<ClinicianDashboardScreen> createState() => _ClinicianDashboardScreenState();
}

class _ClinicianDashboardScreenState extends ConsumerState<ClinicianDashboardScreen>
    with WidgetsBindingObserver {
  Timer? _poll;

  AlertsQuery get _alertsQuery => (status: 'open', severity: null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Live updates: re-pull every 20s so a new message, a resolved alert or a
    // checked-in patient shows without any manual refresh.
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
    ref.invalidate(alertsProvider(_alertsQuery));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // valueOrNull, not .when: on a timer refresh the provider briefly re-enters
    // loading, and reading the last value keeps the screen from flashing a
    // spinner every twenty seconds.
    final overview = ref.watch(overviewProvider).valueOrNull;
    final alerts = ref.watch(alertsProvider(_alertsQuery)).valueOrNull?.items ?? const [];
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
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.xl,
                        ),
                        children: [
                          if (overview != null) ...[
                            _HeadlineRow(overview: overview),
                            const SizedBox(height: AppSpacing.md),
                            _ActiveTodayCard(overview: overview),
                            const SizedBox(height: AppSpacing.md),
                            _AlertStrip(overview: overview),
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          _TriageQueue(alerts: alerts),
                          if (overview != null && overview.nutritionReviews.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            _NutritionReviews(overview: overview),
                          ],
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
            errorBuilder: (_, _, _) => Icon(Icons.forum_rounded, size: 26, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 10),
          Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => context.push('/clinician/more'),
            child: UserAvatar(
              name: user?.name ?? '',
              avatarUrl: user?.avatarUrl,
              accent: AppColors.accentOn(context),
              size: 38,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Headline counts ------------------------------------------------------

class _HeadlineRow extends StatelessWidget {
  const _HeadlineRow({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight, not a bare stretch: inside a ListView the cross-axis is
    // unbounded, so stretching makes both cards infinitely tall and everything
    // below them unreachable. This sizes them to the taller of the two.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _HeadlineCard(
              label: 'TOTAL PATIENTS',
              value: '${overview.patientCount}',
              // Only shown when someone actually registered today; "+0 today"
              // is noise dressed up as news.
              suffix: overview.newPatientsToday > 0 ? '+${overview.newPatientsToday} today' : null,
              suffixColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _HeadlineCard(
              label: 'PENDING SUMMARIES',
              value: '${overview.pendingReviews}',
              suffix: 'in queue',
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({
    required this.label,
    required this.value,
    this.suffix,
    this.suffixColor,
  });

  final String label;
  final String value;
  final String? suffix;
  final Color? suffixColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: scheme.onSurface),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    suffix!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: suffixColor ?? scheme.onSurfaceVariant,
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

// ---- Active today ---------------------------------------------------------

class _ActiveTodayCard extends StatelessWidget {
  const _ActiveTodayCard({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = (overview.appointmentsToday - overview.completedToday).clamp(0, 9999);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.infoBgOn(context),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ACTIVE TODAY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(Icons.event_available_outlined, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${overview.appointmentsToday}',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: scheme.onSurface),
              ),
              const SizedBox(width: 8),
              Text(
                'Scheduled Encounters',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // The design splits this into in-person and telehealth. ClinQ has no
          // telehealth appointments, so the split that IS real is used instead:
          // what has been seen today and what is still to come.
          Row(
            children: [
              _Pill(
                text: 'Completed: ${overview.completedToday}',
                bg: AppColors.primary,
                fg: Colors.white,
              ),
              const SizedBox(width: AppSpacing.sm),
              _Pill(text: 'Remaining: $remaining', bg: AppColors.accentSoftOn(context), fg: AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// ---- Alert strip ----------------------------------------------------------

class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AlertRow(
          icon: Icons.warning_amber_rounded,
          iconBg: AppColors.danger,
          bg: AppColors.dangerBgOn(context),
          label: 'VITALS WARNING',
          labelColor: AppColors.danger,
          detail: '${overview.riskCritical} Critical ${overview.riskCritical == 1 ? 'Patient' : 'Patients'}',
          onTap: () => context.go('/clinician/patients'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AlertRow(
          icon: Icons.priority_high_rounded,
          iconBg: AppColors.primary,
          bg: AppColors.infoBgOn(context),
          label: 'HIGH PRIORITY',
          detail:
              '${overview.highPriorityAlerts} Action ${overview.highPriorityAlerts == 1 ? 'Item' : 'Items'}',
          onTap: () => context.push('/clinician/alerts'),
        ),
        const SizedBox(height: AppSpacing.sm),
        _AlertRow(
          icon: Icons.mail_outline_rounded,
          iconBg: AppColors.primary,
          bg: AppColors.infoBgOn(context),
          label: 'NEW MESSAGES',
          detail: '${overview.unreadMessages} Unread',
          onTap: () => context.go('/clinician/patients'),
        ),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.icon,
    required this.iconBg,
    required this.bg,
    required this.label,
    required this.detail,
    required this.onTap,
    this.labelColor,
  });

  final IconData icon;
  final Color iconBg;
  final Color bg;
  final String label;
  final String detail;
  final Color? labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: labelColor ?? scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Live triage queue ----------------------------------------------------

class _TriageQueue extends StatelessWidget {
  const _TriageQueue({required this.alerts});

  final List<ClinicalAlert> alerts;

  static const _severityOrder = ['emergency', 'urgent', 'warning', 'info'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Worst first, then newest within a severity — "sorted by urgency" has to
    // actually be true, since the doctor reads the top row and acts.
    final sorted = [...alerts]
      ..sort((a, b) {
        final bySeverity =
            _severityOrder.indexOf(a.severity).compareTo(_severityOrder.indexOf(b.severity));
        if (bySeverity != 0) return bySeverity;
        return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
      });
    final shown = sorted.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text('Live Triage Queue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(
              'Sorted by Urgency',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (shown.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.accentOn(context), size: 26),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'No open alerts. Nothing is waiting on triage.',
                    style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                  _TriageRow(alert: shown[i]),
                ],
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Material(
            color: AppColors.infoBgOn(context),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              onTap: () => context.push('/clinician/alerts'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Center(
                  child: Text(
                    'View All Triage (${alerts.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TriageRow extends StatelessWidget {
  const _TriageRow({required this.alert});

  final ClinicalAlert alert;

  static Color _dotColor(String severity) => switch (severity) {
    'emergency' => AppColors.danger,
    'urgent' => const Color(0xFFEA580C),
    'warning' => AppColors.warning,
    _ => const Color(0xFF9CA3AF),
  };

  static String _severityLabel(String severity) => switch (severity) {
    'emergency' => 'Critical',
    'urgent' => 'Urgent',
    'warning' => 'Elevated',
    _ => 'Routine',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dot = _dotColor(alert.severity);
    final isEmergency = alert.severity == 'emergency';

    return InkWell(
      onTap: alert.patientId == null
          ? null
          : () => context.push('/clinician/patients/${alert.patientId}/thread', extra: alert.patientName),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isEmergency ? dot : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: dot, width: 2),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    alert.patientName ?? 'Unknown patient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
                  ),
                ),
                if (alert.createdAt != null)
                  Text(
                    DateFormat('h:mm a').format(alert.createdAt!),
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                alert.detail?.isNotEmpty == true ? alert.detail! : alert.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, height: 1.4, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 6,
                children: [
                  _Tag(
                    _severityLabel(alert.severity),
                    fg: isEmergency ? AppColors.danger : AppColors.primary,
                    bg: isEmergency ? AppColors.dangerBgOn(context) : AppColors.infoBgOn(context),
                  ),
                  if (alert.type.isNotEmpty)
                    _Tag(_humanise(alert.type), fg: AppColors.primary, bg: AppColors.infoBgOn(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _humanise(String type) {
    final words = type.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (words.isEmpty) return words;
    return words[0].toUpperCase() + words.substring(1);
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.fg, required this.bg});

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// ---- Nutrition reviews ----------------------------------------------------

class _NutritionReviews extends StatelessWidget {
  const _NutritionReviews({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final reviews = overview.nutritionReviews;
    final due = reviews.where((r) => r.isDue).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Nutrition Reviews', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (due > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentSoftOn(context),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$due Due',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentOn(context),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final r in reviews) _NutritionCard(review: r),
      ],
    );
  }
}

class _NutritionCard extends StatelessWidget {
  const _NutritionCard({required this.review});

  final NutritionReview review;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quiet = review.lastLogAt == null || DateTime.now().difference(review.lastLogAt!).inDays >= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                'Day ${review.day}/${review.intervalDays}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: review.isDue ? FontWeight.w800 : FontWeight.w500,
                  color: review.isDue ? AppColors.warning : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: quiet ? AppColors.warningBgOn(context) : AppColors.accentSoftOn(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  quiet ? Icons.water_drop_outlined : Icons.restaurant_rounded,
                  size: 20,
                  color: quiet ? AppColors.warning : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(review.flag, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      review.detail,
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.accentSoftOn(context),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => context.push('/clinician/patients/${review.patientId}'),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 13),
                  child: Center(
                    child: Text(
                      'Review Log',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.accentOn(context)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

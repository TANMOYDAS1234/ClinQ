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
import 'widgets/clinic_analytics.dart';

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
    ref.invalidate(clinicAnalyticsProvider);
    ref.invalidate(attentionPatientsProvider);
    ref.invalidate(alertsProvider(_alertsQuery));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // valueOrNull, not .when: on a timer refresh the provider briefly re-enters
    // loading, and reading the last value keeps the screen from flashing a
    // spinner every twenty seconds.
    final overview = ref.watch(overviewProvider).valueOrNull;
    final analytics = ref.watch(clinicAnalyticsProvider).valueOrNull;
    final attention = ref.watch(attentionPatientsProvider).valueOrNull ?? const <PatientListItem>[];
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
                            // "Active today" is gone. It counted appointments
                            // booked through the app, and this clinic does not
                            // book that way — so it read 0 every day and cost a
                            // card's worth of the screen saying nothing.
                            _AlertStrip(overview: overview),
                            if (analytics != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              _MonitoringStrip(analytics: analytics),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                          ],
                          if (attention.isNotEmpty) ...[
                            AttentionListCard(patients: attention),
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
              suffixColor: AppColors.accentOn(context),
              onTap: () => context.go('/clinician/patients'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // Named for what it counts, and tappable. "Pending summaries" was
            // borrowed from the reference design and described nothing in this
            // app: the number is flagged conversations, and there was no way to
            // reach them from the figure telling you they existed.
            child: _HeadlineCard(
              label: 'FLAGGED CHATS',
              value: '${overview.pendingReviews}',
              suffix: 'to review',
              onTap: () => context.push('/clinician/chat-review'),
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
    this.onTap,
  });

  final String label;
  final String value;
  final String? suffix;
  final Color? suffixColor;

  /// Where the number leads. A count with nowhere to go is a number the doctor
  /// has to go and find by hand.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
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

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: card,
      ),
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
        // Care messages only. The total used to include nutrition threads and
        // then send the doctor to the Patients tab, which does not show them.
        if (overview.unreadMessages - overview.unreadNutrition > 0)
          _AlertRow(
            icon: Icons.mail_outline_rounded,
            iconBg: AppColors.primary,
            bg: AppColors.infoBgOn(context),
            label: 'NEW MESSAGES',
            detail: '${overview.unreadMessages - overview.unreadNutrition} Unread',
            onTap: () => context.go('/clinician/patients'),
          ),
        // Its own row, going where these actually live: Chat review, opened on
        // the Nutrition filter.
        if (overview.unreadNutrition > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          _AlertRow(
            icon: Icons.restaurant_rounded,
            iconBg: AppColors.accent,
            bg: AppColors.successBgOn(context),
            label: 'NUTRITION MESSAGES',
            detail: '${overview.unreadNutrition} Unread',
            onTap: () => context.go('/clinician/nutrition'),
          ),
        ],
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

// ---- Continuous-monitoring roll-up ----------------------------------------

/// The dashboard answer to "I have 100+ patients, I can't watch 100 graphs":
/// two counts that surface who needs a look — patients who have gone quiet past
/// their check-in cadence, and patients whose control is drifting out of range.
/// Both drill into the patient list, where each row carries its own sparkline.
class _MonitoringStrip extends StatelessWidget {
  const _MonitoringStrip({required this.analytics});

  final ClinicAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    if (analytics.overdueCheckIns > 0) {
      rows.add(
        _AlertRow(
          icon: Icons.schedule_rounded,
          iconBg: AppColors.warning,
          bg: AppColors.warningBgOn(context),
          label: 'CHECK-INS OVERDUE',
          labelColor: AppColors.warningOn(context),
          detail:
              '${analytics.overdueCheckIns} ${analytics.overdueCheckIns == 1 ? 'patient has' : 'patients have'} gone quiet',
          onTap: () => context.go('/clinician/patients'),
        ),
      );
    }

    if (analytics.trendingWorse > 0) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(
        _AlertRow(
          icon: Icons.trending_up_rounded,
          iconBg: AppColors.danger,
          bg: AppColors.dangerBgOn(context),
          label: 'TRENDING WORSE',
          labelColor: AppColors.danger,
          detail:
              '${analytics.trendingWorse} ${analytics.trendingWorse == 1 ? 'patient' : 'patients'} drifting out of range',
          onTap: () => context.go('/clinician/patients'),
        ),
      );
    }

    // Nothing needs attention — a quiet, reassuring confirmation rather than a
    // blank gap, so the doctor knows monitoring is actually running.
    if (rows.isEmpty) {
      if (analytics.activePatients == 0) return const SizedBox.shrink();
      rows.add(
        _AlertRow(
          icon: Icons.check_circle_outline_rounded,
          iconBg: AppColors.accent,
          bg: AppColors.successBgOn(context),
          label: 'MONITORING',
          detail: 'All patients up to date on check-ins',
          onTap: () => context.go('/clinician/patients'),
        ),
      );
    }

    return Column(children: rows);
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

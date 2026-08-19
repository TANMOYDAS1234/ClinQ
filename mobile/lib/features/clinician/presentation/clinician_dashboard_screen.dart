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
import 'widgets/panel_ui.dart';
import 'widgets/clinic_analytics.dart';
import 'widgets/clinician_notification_sheet.dart';

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
                            const _OverviewHeading(),
                            const SizedBox(height: AppSpacing.md),
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

/// Names what the screen is before the numbers start.
///
/// Four figures and three lists with no heading read as a pile of widgets; one
/// line saying what they add up to is the difference between a dashboard and a
/// dump of counters.
class _OverviewHeading extends StatelessWidget {
  const _OverviewHeading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Operational Overview',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 0),
        Text(
          "Your clinic's high-level status for today.",
          style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
        ),
      ],
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
            'assets/brand/medpin_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) => Icon(Icons.forum_rounded, size: 26, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 8),
          Text(
            'MedPin',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppColors.accentOn(context),
            ),
          ),
          const Spacer(),
          PanelNotificationBell(onTap: () => showClinicianNotifications(context)),
          const SizedBox(width: 4),
          GestureDetector(
            // `go`, not `push`: Profile is one of this shell's own tabs, so
            // pushing it stacked a copy while the bar kept the old tab lit.
            onTap: () => context.go('/clinician/more'),
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
              fontSize: 12,
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
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: scheme.onSurface),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    suffix!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
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

/// The four counters, as a 2x2 grid of tiles.
///
/// Stacked full-width rows before this: four of them pushed the triage queue —
/// the part of the screen with a patient's name on it — below the fold. A grid
/// says the same in half the height, and the pairing reads as "what is wrong"
/// on the left, "what is waiting" on the right.
class _AlertStrip extends StatelessWidget {
  const _AlertStrip({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final careUnread = overview.unreadMessages - overview.unreadNutrition;

    final tiles = <Widget>[
      _StatTile(
        icon: Icons.monitor_heart_outlined,
        value: '${overview.riskCritical}',
        label: overview.riskCritical == 1 ? 'Critical Vital' : 'Critical Vitals',
        // The only tile that carries colour. A red panel among neutral ones is
        // read before anything else on the screen, which is the point — every
        // tile tinted would mean none of them stands out.
        tone: AppColors.dangerOn(context),
        background: AppColors.dangerBgOn(context),
        onTap: () => context.go('/clinician/patients'),
      ),
      _StatTile(
        icon: Icons.error_outline_rounded,
        value: '${overview.highPriorityAlerts}',
        label: overview.highPriorityAlerts == 1 ? 'Action Item' : 'Action Items',
        tone: scheme.onSurface,
        background: scheme.surfaceContainerLow,
        onTap: () => context.push('/clinician/alerts'),
      ),
      _StatTile(
        icon: Icons.forum_outlined,
        value: '$careUnread',
        label: 'Unread Msgs',
        tone: AppColors.accentOn(context),
        background: AppColors.infoBgOn(context),
        onTap: () => context.go('/clinician/patients'),
      ),
      _StatTile(
        icon: Icons.restaurant_outlined,
        value: '${overview.unreadNutrition}',
        label: 'Nutrition Msgs',
        tone: scheme.onSurface,
        background: scheme.surfaceContainerLow,
        onTap: () => context.go('/clinician/nutrition'),
      ),
    ];

    return Column(
      children: [
        Row(children: [
          Expanded(child: tiles[0]),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: tiles[1]),
        ]),
        const SizedBox(height: AppSpacing.sm),
        Row(children: [
          Expanded(child: tiles[2]),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: tiles[3]),
        ]),
      ],
    );
  }
}

/// One counter: an icon, the figure, and what it counts.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.tone,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;

  /// Colours the icon, the figure and the caption together, so a tile reads as
  /// one object rather than three.
  final Color tone;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: tone),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: tone,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
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
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: labelColor ?? scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 0),
                              Text(
                                detail,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                              ),
                            ],
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
        const Text('Live Triage Queue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
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
                    style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          )
        else
          for (final a in shown) _TriageCard(alert: a),
        if (alerts.length > shown.length)
          SizedBox(
            width: double.infinity,
            child: Material(
              color: AppColors.infoBgOn(context),
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                onTap: () => context.push('/clinician/alerts'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'View all triage (${alerts.length})',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

class _TriageCard extends StatelessWidget {
  const _TriageCard({required this.alert});

  final ClinicalAlert alert;

  static Color _sevColor(String severity) => switch (severity) {
    'emergency' => AppColors.danger,
    'urgent' => const Color(0xFFEA580C),
    'warning' => AppColors.warning,
    _ => const Color(0xFF9CA3AF),
  };

  static String _sevLabel(String severity) => switch (severity) {
    'emergency' => 'Critical',
    'urgent' => 'Urgent',
    'warning' => 'Elevated',
    _ => 'Routine',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sev = AppColors.toneOn(context, _sevColor(alert.severity));
    final quote = (alert.detail?.trim().isNotEmpty ?? false) ? alert.detail!.trim() : null;
    final canOpen = alert.patientId != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: sev),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        UserAvatar(name: alert.patientName ?? '?', avatarUrl: null, accent: sev, size: 40),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.patientName ?? 'Unknown patient',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 0),
                              Text(
                                '${_sevLabel(alert.severity)} · ${alert.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: sev),
                              ),
                            ],
                          ),
                        ),
                        if (alert.createdAt != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('h:mm a').format(alert.createdAt!),
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                    if (quote != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          quote,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, height: 1.35, fontStyle: FontStyle.italic, color: scheme.onSurface),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: canOpen
                            ? () => context.push('/clinician/patients/${alert.patientId}/thread', extra: alert.patientName)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: const Text('Review Case', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      ),
                    ),
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

// ---- Nutrition reviews ----------------------------------------------------

/// The doctor's task list — the nutrition reviews that are due (or coming up),
/// each an actionable row opening that patient. Due first; the rest are shown as
/// "coming up" context, and anything past the first few defers to the Nutrition
/// tab so Home never turns into a long list.
/// Nutrition reviews, drawn as progress through each patient's review cycle.
///
/// A row per patient with a bar showing how far into the cycle they are. The
/// bar is the point: "Day 7/7" and "Day 2/7" are the same sentence until you
/// see one bar full and the other barely started, and the doctor is scanning
/// for the full ones.
class _NutritionReviews extends StatelessWidget {
  const _NutritionReviews({required this.overview});

  final ClinicOverview overview;

  @override
  Widget build(BuildContext context) {
    // Due first, then most-overdue within — the top row is the one to do.
    final reviews = [...overview.nutritionReviews]
      ..sort((a, b) {
        final byDue = (b.isDue ? 1 : 0).compareTo(a.isDue ? 1 : 0);
        if (byDue != 0) return byDue;
        return b.day.compareTo(a.day);
      });
    final shown = reviews.take(4).toList();
    final due = reviews.where((r) => r.isDue).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelSectionHeader(
          title: 'Nutrition Reviews Due',
          trailing: due == 0
              ? null
              : PanelPill(label: '$due Due', color: AppColors.warningOn(context)),
        ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ReviewProgressCard(review: r),
          ),
        if (reviews.length > shown.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: AppColors.accentOn(context),
              ),
              onPressed: () => context.go('/clinician/nutrition'),
              child: Text(
                'View all ${reviews.length}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
  }
}

/// One patient's position in their review cycle.
class _ReviewProgressCard extends StatelessWidget {
  const _ReviewProgressCard({required this.review});

  final NutritionReview review;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = review;
    final total = r.intervalDays <= 0 ? 1 : r.intervalDays;
    final progress = (r.day / total).clamp(0.0, 1.0);

    // Brand blue throughout. On a daily cadence every bar is either empty or
    // full, so red on the full ones turned the whole section red every morning
    // — an alarm that fires daily stops being an alarm. Being due is said by
    // the "Day 7/7" label and the count in the heading instead.
    final tone = AppColors.accentOn(context);

    return PanelCard(
      // Straight into the conversation, because reviewing a food log means
      // reading what was logged and replying to it. The record is still a tap
      // away from the thread header. Falls back to the record when the patient
      // has no nutrition thread yet.
      onTap: () => context.push(
        r.nutritionSessionId != null
            ? '/clinician/chat-review/${r.nutritionSessionId}'
            : '/clinician/patients/${r.patientId}',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Day ${r.day}/$total',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: r.isDue ? tone : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            // What the doctor can actually act on: whether the patient has been
            // logging. An empty week is why a review matters, and it is the one
            // thing the cycle number alone never says.
            r.mealsThisWeek == 0
                ? 'No meals logged this week'
                : '${r.mealsThisWeek} meals logged this week',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
        ],
      ),
    );
  }
}


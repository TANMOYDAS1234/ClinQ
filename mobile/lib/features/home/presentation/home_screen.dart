import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/hero_band.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../glucose/domain/glucose_trends.dart';
import '../../glucose/presentation/glucose_providers.dart';
import '../../glucose/presentation/log_glucose_sheet.dart';
import '../../glucose/presentation/widgets/glucose_stats_row.dart';
import '../../glucose/presentation/widgets/glucose_trend_chart.dart';
import '../../labtests/domain/lab_tests.dart';
import '../../labtests/presentation/lab_tests_providers.dart';
import '../../medications/presentation/medications_providers.dart';
import '../domain/care_summary.dart';
import 'home_providers.dart';

/// The patient's home: their care as the clinic has set it out.
///
/// Read-only by design. This is the answer to "what am I supposed to be doing",
/// and every action it implies — logging a meal, ticking off a dose, asking a
/// question — already has a tab of its own. A second place to do those things
/// would be a second place to keep them in sync.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  Timer? _poll;

  /// The home screen shows what the clinic has decided — a new prescription, a
  /// diet plan the dietician just sent, a fresh HbA1c. None of that is the
  /// patient's own doing, so waiting for them to pull-to-refresh means showing
  /// them yesterday's care and giving no sign there is anything newer.
  static const _pollInterval = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the background is the likeliest moment for something to
    // have changed, so check at once rather than waiting out the timer.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    ref.invalidate(careSummaryProvider);
    // Also the source the on-device reminders are built from: a dose the doctor
    // has just retimed should move on this screen *and* stop ringing at the old
    // hour, without waiting for the app to be backgrounded and reopened.
    ref.invalidate(medicationsListProvider);
    // Today's doses too, so a dose ticked off in the Medicines tab moves this
    // screen's progress bar the moment the patient comes back to it.
    ref.invalidate(todayScheduleProvider);
    // And the lab reports: a report uploaded from the Profile tab, or an
    // analysis that finished on the server a minute after the upload, both have
    // to land here without the patient knowing to come back and pull down.
    ref.invalidate(labTestsProvider);
    // The glucose chart and the "Current glucose" tile above it both read this,
    // so a reading logged from anywhere in the app shows on both at once.
    ref.invalidate(glucoseTrendsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    final asyncCare = ref.watch(careSummaryProvider);
    // Read the last value during a background refresh: .when would drop the
    // whole screen to a spinner every thirty seconds.
    final loaded = asyncCare.valueOrNull;
    final async = loaded != null ? AsyncData<CareSummary>(loaded) : asyncCare;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _BrandHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: async.when(
                  loading:
                      () => const Center(child: CircularProgressIndicator()),
                  error:
                      (_, _) => ListView(
                        children: [
                          const SizedBox(height: 140),
                          const Center(
                            child: Text('Could not load your care summary'),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Center(
                            child: OutlinedButton(
                              onPressed:
                                  () => ref.invalidate(careSummaryProvider),
                              child: const Text('Retry'),
                            ),
                          ),
                        ],
                      ),
                  // Zero padding on the list so the hero can run to both
                  // edges; everything after it is padded individually. A
                  // colour that stops short of the screen edge reads as a
                  // card, not as the ground the screen is standing on.
                  data:
                      (care) => ListView(
                        padding: const EdgeInsets.only(bottom: 110),
                        children: [
                          _Hero(care: care, name: user?.name ?? ''),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              AppSpacing.md,
                              AppSpacing.md,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Age, gender, email and address used to sit
                                // here. They are who the record belongs to,
                                // not what the patient opened the app to find
                                // out, and four lines of text that never
                                // change pushed the actual care down the page.
                                // They live in Profile, which is where someone
                                // goes when they want to check them.
                                const SizedBox(height: AppSpacing.lg),

                                _FactGrid(care: care),

                                const SizedBox(height: AppSpacing.md),
                                const _GlucoseCard(),

                                // Directly under glucose: both answer "what do my numbers
                                // say", and an ordered test sitting undone is the thing on
                                // this screen most likely to be holding up the next
                                // consultation.
                                const SizedBox(height: AppSpacing.md),
                                const _LabReports(),

                                if (care.profile.allergies.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  _Allergies(items: care.profile.allergies),
                                ],

                                if (care.dietPlan != null) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  _DietPlanCard(plan: care.dietPlan!),
                                ],

                                // Each section now carries its own heading inside its
                                // card, so the spacing between them is uniform and the
                                // page reads as one stack rather than headings and
                                // content taking turns.
                                if (care.medications.isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  _Medicines(items: care.medications),
                                ],

                                const SizedBox(height: AppSpacing.md),
                                _FoodLogs(items: care.recentFoodLogs),
                              ],
                            ),
                          ),
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

class _BrandHeader extends ConsumerWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/brand/medpin_emblem.png',
            height: 30,
            errorBuilder:
                (_, _, _) => Icon(
                  Icons.favorite_rounded,
                  size: 26,
                  color: AppColors.accentOn(context),
                ),
          ),
          const SizedBox(width: 8),
          Text(
            'MedPin',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.accentOn(context),
            ),
          ),
          const Spacer(),
          // Tapping it opens Profile, the same as the doctor's header — the
          // photo is where people expect their own account to live.
          GestureDetector(
            onTap: () => context.go('/profile'),
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

// ---- Glucose monitoring ---------------------------------------------------

/// The patient's own glucose trend on their home — the same picture the clinic
/// watches, so "how am I doing?" has an answer right here — with the one
/// low-friction place to add a reading, since forgetting to check in is the
/// thing that quietly breaks continuous monitoring.
class _GlucoseCard extends ConsumerWidget {
  const _GlucoseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);
    final trends = ref.watch(glucoseTrendsProvider);

    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.monitor_heart_rounded,
            title: 'Your glucose',
            actionLabel: 'Add',
            actionIcon: Icons.add_rounded,
            onAction: () => showLogGlucoseSheet(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          trends.when(
            loading:
                () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
            error:
                (_, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(
                    'Could not load your readings.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
            data: (t) {
              if (t.series.length < 2) return _CheckInPrompt(accent: accent);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GlucoseStatsRow(stats: t.stats),
                  const SizedBox(height: AppSpacing.md),
                  GlucoseTrendChart(trends: t),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Shown when there are too few readings to draw a trend — a friendly first
/// check-in nudge in place of an empty chart.
class _CheckInPrompt extends StatelessWidget {
  const _CheckInPrompt({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Log a glucose reading every few days and your trend builds here — the same one your doctor sees.',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => showLogGlucoseSheet(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add your first reading'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Facts ----------------------------------------------------------------

class _FactGrid extends ConsumerWidget {
  const _FactGrid({required this.care});

  final CareSummary care;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = care.profile;
    final hba1c = care.latestHba1c;
    // Oldest to newest, so the last point is the most recent reading.
    final latestGlucose =
        ref.watch(glucoseTrendsProvider).valueOrNull?.series.lastOrNull;

    // Facts, not widgets: the grid decides afterwards whether each one is drawn
    // as a square tile or, when it is the odd one out at the end, as a wide bar.
    final facts = <_Fact>[
      if (p.conditionLabel != null) _Fact('Condition', p.conditionLabel!),
      // The doctor's next-visit instruction — arguably the most useful single
      // thing on this screen: "when do I come back?".
      if (care.followUpOn != null)
        _Fact('Next Visit', DateFormat('d MMM yyyy').format(care.followUpOn!)),
      // One measurement per tile. Crammed into a single "BMI / Wt / Ht" cell the
      // value wrapped onto a second line, which made that row taller than the
      // one beside it and broke the grid — and three numbers separated by
      // slashes is a thing to decode rather than read.
      if (p.bmi != null) _Fact('BMI', '${p.bmi}'),
      if (p.weightKg != null) _Fact('Weight', '${p.weightKg} kg'),
      if (p.heightCm != null) _Fact('Height', '${p.heightCm} cm'),
      if (p.bloodPressure != null)
        _Fact(
          'Blood Pressure',
          '${p.bloodPressure!.label} mmHg',
          // Red only when above this patient's own target — plain otherwise, so a
          // number they cannot act on tonight is not an alarm.
          color: p.bloodPressure!.isHigh ? AppColors.danger : null,
        ),
      if (p.reviewLabel != null) _Fact('Food-log review', p.reviewLabel!),
      // The newest reading, beside the numbers it belongs with. The chart below
      // shows the shape of the last month; this answers the simpler question a
      // patient asks first — where am I right now.
      if (latestGlucose != null)
        _Fact(
          'Current glucose',
          '${latestGlucose.value} mg/dL',
          // Flagged by the server against the clinic's own range, not by a
          // threshold copied into the app.
          color: latestGlucose.isOutOfRange ? AppColors.danger : null,
        ),
      if (hba1c != null)
        _Fact(
          'Last HbA1c',
          '${hba1c.percentage}%${hba1c.isHigh ? ' (High)' : ''}',
          // Coloured only when it is above this patient's own target — a red
          // number they cannot act on tonight is alarm without information, so
          // it stays plain when the result is where the doctor wants it.
          color: hba1c.isHigh ? AppColors.danger : null,
        ),
    ];

    if (facts.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < facts.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          // Which facts the record holds decides how many there are, so the
          // count is odd as often as it is even. A lone tile stretched across
          // the full width reads as a mistake; the same fact laid along that
          // width — label left, value right — reads as a summary line, which is
          // what it is.
          if (i + 1 >= facts.length)
            _FactCard(fact: facts[i], wide: true)
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _FactCard(fact: facts[i])),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _FactCard(fact: facts[i + 1])),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One fact on the grid: what it is, what it says, and whether that value is
/// outside the target the clinic set.
class _Fact {
  const _Fact(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.fact, this.wide = false});

  final _Fact fact;

  /// Label and value side by side across the full width, for the odd tile at
  /// the end of the grid.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final label = Text(
      fact.label,
      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
    );
    final value = Text(
      fact.value,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: fact.color ?? scheme.onSurface,
      ),
    );

    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child:
          wide
              ? Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: AppSpacing.sm),
                  value,
                ],
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 4), value],
              ),
    );
  }
}

class _Allergies extends StatelessWidget {
  const _Allergies({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerBgOn(context).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.dangerOn(context).withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dangerous_outlined,
                size: 21,
                color: AppColors.dangerOn(context),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Allergies & Intolerances',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.dangerOn(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.dangerOn(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Diet plan ------------------------------------------------------------

class _DietPlanCard extends StatelessWidget {
  const _DietPlanCard({required this.plan});

  final PatientDietPlan plan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Keeps its accent wash rather than the plain card the others use — this is
    // the one section on the screen written by a person for this patient, and it
    // should not look like another read-out.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoftOn(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.accentOn(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.restaurant_rounded,
            title: 'Current Diet Plan',
            trailing:
                plan.sharedAt == null
                    ? null
                    : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Text(
                        'Sent ${DateFormat('d MMM').format(plan.sharedAt!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
          ),
          if (plan.goal.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Goal: ',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: plan.goal),
                ],
              ),
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
          ],
          if (plan.meals.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < plan.meals.length; i += 2) ...[
              if (i > 0) const SizedBox(height: AppSpacing.sm),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _MealCard(meal: plan.meals[i])),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child:
                          i + 1 < plan.meals.length
                              ? _MealCard(meal: plan.meals[i + 1])
                              : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ],
          if (plan.avoid.isNotEmpty || plan.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed:
                    () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => _FullPlanSheet(plan: plan),
                    ),
                child: Text(
                  'View full plan',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentOn(context),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal});

  final PlanMeal meal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meal.time.isEmpty ? meal.name : '${meal.name} • ${meal.time}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            meal.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The whole plan, including the avoid list and any closing note. Shown as a
/// sheet rather than a PDF: there is no document to open, and a link that
/// promised one would be a link that breaks.
class _FullPlanSheet extends StatelessWidget {
  const _FullPlanSheet({required this.plan});

  final PatientDietPlan plan;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder:
          (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              const Text(
                'Your diet plan',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (plan.dieticianName != null) ...[
                const SizedBox(height: 4),
                Text(
                  'From ${plan.dieticianName}',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (plan.goal.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  plan.goal,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
              for (final meal in plan.meals) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  meal.time.isEmpty ? meal.name : '${meal.name} · ${meal.time}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                for (final item in meal.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '•  $item',
                      style: const TextStyle(fontSize: 14, height: 1.45),
                    ),
                  ),
                if (meal.notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      meal.notes,
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
              if (plan.avoid.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'Best avoided',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final item in plan.avoid)
                      Chip(
                        label: Text(item),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (plan.notes.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  plan.notes,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
    );
  }
}

// ---- Medicines ------------------------------------------------------------

class _Medicines extends ConsumerWidget {
  const _Medicines({required this.items});

  final List<CareMedication> items;

  /// "20:00" as the patient reads a clock.
  static String _clock(String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first);
    if (h == null || parts.length < 2) return hhmm;
    final suffix = h < 12 ? 'AM' : 'PM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${parts[1]} $suffix';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);
    final today = ref.watch(todayScheduleProvider).valueOrNull;

    final slots = today?.slots ?? const [];
    final done = slots.where((s) => s.status == 'taken').length;
    // The next thing to take: the earliest slot still waiting. Skipped and
    // missed ones are behind the patient and are not what they came here for.
    final next = slots.where((s) => s.status == 'pending').firstOrNull;

    return _HomeCard(
      // stretch, not the default centre: without it each row shrinks to the
      // width of its own text and floats in the middle, so a list of medicines
      // has a different left edge on every line and nothing to read down.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardHeader(
            icon: Icons.medication_rounded,
            title: 'Medicines',
            trailing:
                slots.isEmpty
                    ? _CountBadge(count: items.length)
                    : _CountBadge.text('$done of ${slots.length} taken'),
          ),

          // Today, before the prescription. A patient opening this screen wants
          // "what do I take next", not "what am I on" — they already know what
          // they are on. The list below answers the second question and stays,
          // because the pharmacy and the family carer both need it.
          if (slots.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: slots.isEmpty ? 0 : done / slots.length,
                minHeight: 7,
                backgroundColor: accent.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Icon(
                    next == null
                        ? Icons.task_alt_rounded
                        : Icons.schedule_rounded,
                    size: 17,
                    color: accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                        next == null
                            ? Text(
                              'Every dose for today is marked.',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            )
                            : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Next dose  ${_clock(next.time)}',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(height: 0),
                                Text(
                                  [
                                    next.name,
                                    next.dose,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/medications'),
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),
          Text(
            'YOUR PRESCRIPTION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < items.length; i++) ...[
            // Inset, not edge to edge: the rule separates the two names, and
            // stopping it short of the card wall keeps the list feeling like one
            // block rather than a stack of separate strips.
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 48, top: 8, bottom: 8),
                child: Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.medication_liquid_rounded,
                    size: 17,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].scheduleLabel,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The small count on a section header — "how many of these are there" answered
/// without making the reader count the rows.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required int count}) : label = '$count';
  const _CountBadge.text(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOn(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: accent,
        ),
      ),
    );
  }
}

// ---- Food logs ------------------------------------------------------------

class _FoodLogs extends StatelessWidget {
  const _FoodLogs({required this.items});

  final List<CareFoodLog> items;

  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('d MMM').format(at);
  }

  static String _meal(String type) =>
      type.isEmpty ? '' : type[0].toUpperCase() + type.substring(1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Padding only at the top: the rail below runs to both card walls, so a
    // half-visible card at the right edge shows there is more to swipe to.
    return _HomeCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.photo_camera_rounded,
            title: 'Recent Food Logs',
            actionLabel: items.isEmpty ? null : 'View all',
            // The meal history, not the dietician thread. Logging happens in
            // the conversation, so "Log a meal" below rightly opens it — but
            // "View all" next to a row of past meals means show me the rest of
            // them, and dropping the patient into a chat is not that.
            onAction:
                items.isEmpty ? null : () => context.push('/food-log/history'),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                AppSpacing.lg,
                0,
                AppSpacing.lg,
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.restaurant_menu_rounded,
                    size: 34,
                    color: scheme.outlineVariant,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Text(
                    'No meals logged yet',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 0),
                  Text(
                    'Photos of what you eat help your dietician give better advice.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton.tonalIcon(
                    onPressed: () => context.go('/food-log'),
                    icon: const Icon(Icons.add_a_photo_rounded, size: 18),
                    label: const Text('Log a meal'),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              // One fixed rectangle now that the caption sits on the photo,
              // but still scaled by the text factor: the overlaid note grows
              // with the system setting and would otherwise clip.
              height: MediaQuery.textScalerOf(context).scale(168),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                // Negative-free bleed: the list starts at the card's text edge
                // and ends past it, so the last card is not jammed against the
                // wall.
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  bottom: AppSpacing.md,
                  right: AppSpacing.md,
                ),
                itemCount: items.length,
                separatorBuilder:
                    (_, _) => const SizedBox(width: AppSpacing.sm),
                itemBuilder:
                    (context, i) => _FoodLogTile(
                      log: items[i],
                      when: _when(items[i].createdAt),
                      meal: _meal(items[i].mealType),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One meal in the rail.
///
/// The photo *is* the tile rather than sitting in a box above a caption. A
/// meal photograph is the only genuinely appealing image this app has, and the
/// old layout spent two thirds of the tile on a white caption panel around a
/// thumbnail. The caption now rides on the picture behind a scrim, which is
/// both the editorial treatment the reference kit uses and the one that gives
/// the photograph the room to be worth looking at.
class _FoodLogTile extends StatelessWidget {
  const _FoodLogTile({
    required this.log,
    required this.when,
    required this.meal,
  });

  final CareFoodLog log;
  final String when;
  final String meal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasPhoto = log.photoUrl != null;
    final note = log.note.trim();

    return SizedBox(
      width: 148,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasPhoto)
              AuthedImage(path: log.photoUrl!, fit: BoxFit.cover)
            else
              Center(
                child: Icon(
                  Icons.restaurant_rounded,
                  size: 32,
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),

            // The scrim. Without it a caption over a bright plate is
            // unreadable, and over a dark one it disappears — this makes the
            // bottom third predictable whatever the photograph is doing.
            if (hasPhoto)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),

            Positioned(
              left: AppSpacing.sm,
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    [
                      if (meal.isNotEmpty) meal,
                      if (when.isNotEmpty) when,
                    ].join('  •  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: hasPhoto ? Colors.white : scheme.onSurface,
                    ),
                  ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.3,
                        color:
                            hasPhoto
                                ? Colors.white.withValues(alpha: 0.85)
                                : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lab reports: what the doctor has asked for, and what came back.
///
/// The tests live under Profile, which is where a patient goes to *manage*
/// them. But an ordered test the patient has not had done yet is one of the few
/// things on this screen they are actually expected to act on, and a result that
/// has come back is one of the few that changes what happens next. Both belong
/// where they will be seen.
class _LabReports extends ConsumerWidget {
  const _LabReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(labTestsProvider);

    // Read the last value through a refresh: this sits mid-page, and dropping it
    // to a spinner every thirty seconds would make the screen twitch.
    final view = async.valueOrNull;

    return _HomeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.biotech_rounded,
            title: 'Lab Reports',
            actionLabel: 'Upload',
            actionIcon: Icons.file_upload_outlined,
            onAction: () => context.push('/profile/tests'),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (view == null && async.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          else if (view == null)
            Text(
              'Could not load your reports.',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            )
          else
            ..._body(context, scheme, view),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    ColorScheme scheme,
    LabTestsView view,
  ) {
    // A test the doctor advised and the patient has not uploaded anything for.
    // Matched on name because that is all the advice carries — the prescription
    // records a test name, not an id.
    final uploaded =
        view.results.map((r) => r.testName.trim().toLowerCase()).toSet();
    final pending =
        view.advised
            .where((t) => !uploaded.contains(t.trim().toLowerCase()))
            .toList();
    final recent = view.results.take(3).toList();

    if (pending.isEmpty && recent.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No reports yet.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 0),
              Text(
                'Upload a photo or PDF of a lab report and your doctor sees the results here.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      if (pending.isNotEmpty) _AdvisedTests(tests: pending),
      if (pending.isNotEmpty && recent.isNotEmpty)
        const SizedBox(height: AppSpacing.md),
      for (var i = 0; i < recent.length; i++) ...[
        if (i > 0)
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 8, bottom: 8),
            child: Divider(
              height: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        _LabResultRow(result: recent[i]),
      ],
      if (view.results.length > recent.length) ...[
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push('/profile/tests'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentOn(context),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Text('View all ${view.results.length} reports'),
          ),
        ),
      ],
    ];
  }
}

/// Tests the doctor ordered that have not come back yet.
class _AdvisedTests extends StatelessWidget {
  const _AdvisedTests({required this.tests});

  final List<String> tests;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOn(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assignment_outlined, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tests.length == 1
                      ? 'Your doctor has asked for 1 test'
                      : 'Your doctor has asked for ${tests.length} tests',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final t in tests.take(6))
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Text(
                    t,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (tests.length > 6)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '+${tests.length - 6} more',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One uploaded report: what it was, when, and what came of it.
class _LabResultRow extends StatelessWidget {
  const _LabResultRow({required this.result});

  final LabResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);
    final abnormal = result.abnormal.length;
    final status = result.analysisStatus;

    // Red only for a value actually outside its range. "Still being read" and
    // "could not be read" are states of the app, not of the patient's health,
    // and colouring them like a bad result would be a false alarm.
    final (String label, Color fg, Color bg)? chip = switch (status) {
      'done' when abnormal > 0 => (
        abnormal == 1 ? '1 out of range' : '$abnormal out of range',
        AppColors.dangerOn(context),
        AppColors.dangerOn(context).withValues(alpha: 0.10),
      ),
      'done' => (
        'All in range',
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
      'pending' => (
        'Being read',
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
      'failed' || 'unsupported' => (
        'Not read',
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
      ),
      _ => null,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.description_rounded, size: 17, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.testName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (result.createdAt != null)
                    Text(
                      DateFormat('d MMM yyyy').format(result.createdAt!),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (result.createdAt != null && chip != null)
                    Text(
                      '  ·  ',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (chip != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: chip.$3,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        chip.$1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: chip.$2,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The card every section on this screen sits in.
///
/// The screen used to speak three visual languages at once: glucose and the
/// diet plan were self-contained cards with their heading inside, while
/// medicines and food logs were a bare heading floating above loose content.
/// Scrolling it felt like scrolling two different screens. One shell, used by
/// all of them, is what makes it read as one page.
///
/// Matches `PanelCard` in the doctor's panel — same radius, same hairline, same
/// shadow — so a patient and their doctor are looking at the same product.
class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B1B33).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A section heading inside a card: the icon on its tinted plate, the title, and
/// an optional action on the right.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.title,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  /// A badge instead of a button — used where the right-hand slot carries a
  /// fact rather than something to tap.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOn(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        if (trailing != null)
          trailing!
        // The icon is drawn only where it says something the word does not —
        // "+" for Add, an upload mark for Upload. "View all" was getting a
        // generic arrow purely because the slot existed, and a decoration
        // nobody asked for is what makes a section look cheap.
        else if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              visualDensity: VisualDensity.compact,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (actionIcon != null) ...[
                  Icon(actionIcon, size: 18),
                  const SizedBox(width: 4),
                ],
                Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The clinic's risk assessment, beside the patient's own name.
///
/// Shown at the clinic's request. Worth being clear about what it is: a band
/// the doctor set on the record, not something the app worked out — which is
/// why it reads as a label rather than a warning, and why "low" gets no badge
/// at all.
class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.profile});

  final CareProfile profile;

  @override
  Widget build(BuildContext context) {
    final critical =
        profile.riskBand == 'critical' || profile.riskBand == 'high';
    final fg = critical ? AppColors.danger : AppColors.warning;
    final bg =
        critical
            ? AppColors.dangerBgOn(context)
            : AppColors.warningBgOn(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            profile.riskLabel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Home's band: the patient's most recent reading, at a size nothing else on
/// the screen competes with.
class _Hero extends ConsumerWidget {
  const _Hero({required this.care, required this.name});

  final CareSummary care;
  final String name;

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Coloured by the server's own triage flag rather than by re-deriving
  /// thresholds here. The engine already decided, and two opinions about
  /// whether a reading is high is one too many.
  static (Color, String) _status(String? flag) => switch (flag) {
    'severe_low' || 'low' => (AppColors.danger, 'Below target'),
    'severe_high' || 'high' => (AppColors.warning, 'Above target'),
    _ => (AppColors.success, 'In range'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trends = ref.watch(glucoseTrendsProvider).valueOrNull;
    final series = trends?.series ?? const <GlucoseTrendPoint>[];
    final latest = series.isEmpty ? null : series.last;
    final (statusColor, statusLabel) = _status(latest?.flag);

    return HeroBand(
      eyebrow: _greeting(),
      title: name.isEmpty ? 'Welcome' : name.split(' ').first,
      trailing:
          care.profile.showRisk ? _RiskBadge(profile: care.profile) : null,
      figure:
          latest == null
              ? null
              : HeroFigure(
                value: '${latest.value.round()}',
                unit: 'mg/dL',
                statusLabel: statusLabel,
                statusColor: statusColor,
                caption:
                    latest.at == null
                        ? 'Latest reading'
                        : 'Latest reading  •  ${DateFormat('d MMM, h:mm a').format(latest.at!)}',
              ),
      footer:
          series.length > 2
              ? HeroSpark(
                values: series.map((p) => p.value.toDouble()).toList(),
              )
              : null,
      child:
          latest == null
              ? _CheckInPrompt(accent: AppColors.accentOn(context))
              : null,
    );
  }
}

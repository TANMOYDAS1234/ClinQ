import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/authed_image.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../glucose/presentation/glucose_providers.dart';
import '../../glucose/presentation/log_glucose_sheet.dart';
import '../../glucose/presentation/widgets/glucose_stats_row.dart';
import '../../glucose/presentation/widgets/glucose_trend_chart.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
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
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => ListView(
                    children: [
                      const SizedBox(height: 140),
                      const Center(child: Text('Could not load your care summary')),
                      const SizedBox(height: AppSpacing.md),
                      Center(
                        child: OutlinedButton(
                          onPressed: () => ref.invalidate(careSummaryProvider),
                          child: const Text('Retry'),
                        ),
                      ),
                    ],
                  ),
                  data: (care) => ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.md,
                      AppSpacing.md,
                      110,
                    ),
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              user?.name ?? '',
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                            ),
                          ),
                          // The clinic's own assessment, shown only for the
                          // bands that mean something. "Low Risk" beside
                          // someone's name is a label doing no work.
                          if (care.profile.showRisk) ...[
                            const SizedBox(width: AppSpacing.sm),
                            _RiskBadge(profile: care.profile),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (user?.dateOfBirth != null) '${_age(user!.dateOfBirth!)} y/o',
                          if (user?.gender != null && user!.gender != 'undisclosed')
                            _cap(user.gender!),
                        ].join('  •  '),
                        style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      _FactGrid(care: care),

                      const SizedBox(height: AppSpacing.md),
                      const _GlucoseCard(),

                      if (care.profile.allergies.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _Allergies(items: care.profile.allergies),
                      ],

                      if (care.dietPlan != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _DietPlanCard(plan: care.dietPlan!),
                      ],

                      if (care.medications.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        const _SectionTitle(icon: Icons.medication_outlined, text: 'Current Medicines'),
                        const SizedBox(height: AppSpacing.sm),
                        _Medicines(items: care.medications),
                      ],

                      const SizedBox(height: AppSpacing.lg),
                      _SectionTitle(
                        icon: Icons.photo_camera_outlined,
                        text: 'Recent Food Logs',
                        action: care.recentFoodLogs.isEmpty ? null : 'View All',
                        onAction: () => context.go('/food-log'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _FoodLogs(items: care.recentFoodLogs),
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

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) years--;
    return years;
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _BrandHeader extends ConsumerWidget {
  const _BrandHeader();

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
            errorBuilder: (_, _, _) =>
                Icon(Icons.favorite_rounded, size: 26, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 10),
          Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.monitor_heart_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              const Expanded(child: Text('Your glucose', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              TextButton.icon(
                onPressed: () => showLogGlucoseSheet(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(foregroundColor: accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          trends.when(
            loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
            error: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Could not load your readings.', style: TextStyle(color: scheme.onSurfaceVariant)),
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
          style: TextStyle(fontSize: 13.5, height: 1.4, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => showLogGlucoseSheet(context),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('Add your first reading'),
            style: FilledButton.styleFrom(backgroundColor: accent, minimumSize: const Size.fromHeight(46)),
          ),
        ),
      ],
    );
  }
}

// ---- Facts ----------------------------------------------------------------

class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.care});

  final CareSummary care;

  @override
  Widget build(BuildContext context) {
    final p = care.profile;
    final hba1c = care.latestHba1c;

    final tiles = <Widget>[
      if (p.conditionLabel != null) _FactCard(label: 'Condition', value: p.conditionLabel!),
      if (p.bmi != null || p.weightKg != null || p.heightCm != null)
        _FactCard(
          label: 'BMI / Wt / Ht',
          value: [
            if (p.bmi != null) '${p.bmi}',
            if (p.weightKg != null) '${p.weightKg}kg',
            if (p.heightCm != null) '${p.heightCm}cm',
          ].join(' / '),
        ),
      if (p.reviewLabel != null) _FactCard(label: 'Review Interval', value: p.reviewLabel!),
      if (hba1c != null)
        _FactCard(
          label: 'Last HbA1c',
          value: '${hba1c.percentage}%${hba1c.isHigh ? ' (High)' : ''}',
          // Coloured only when it is above this patient's own target — a red
          // number they cannot act on tonight is alarm without information, so
          // it stays plain when the result is where the doctor wants it.
          valueColor: hba1c.isHigh ? AppColors.danger : null,
        ),
    ];

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
              color: valueColor ?? scheme.onSurface,
            ),
          ),
        ],
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
        border: Border.all(color: AppColors.dangerOn(context).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dangerous_outlined, size: 21, color: AppColors.dangerOn(context)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Allergies & Intolerances',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.dangerOn(context)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.dangerOn(context),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 13,
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoftOn(context).withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accentOn(context).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.restaurant_rounded, size: 20, color: AppColors.accentOn(context)),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'Current Diet Plan',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
              if (plan.sharedAt != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    'Sent ${DateFormat('d MMM').format(plan.sharedAt!)}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ),
            ],
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
              style: const TextStyle(fontSize: 14.5, height: 1.45),
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
                      child: i + 1 < plan.meals.length
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
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _FullPlanSheet(plan: plan),
                ),
                child: Text(
                  'View full plan',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.accentOn(context)),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meal.time.isEmpty ? meal.name : '${meal.name} • ${meal.time}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            meal.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600),
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
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const Text('Your diet plan', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          if (plan.dieticianName != null) ...[
            const SizedBox(height: 4),
            Text(
              'From ${plan.dieticianName}',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
          if (plan.goal.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(plan.goal, style: const TextStyle(fontSize: 15, height: 1.5)),
          ],
          for (final meal in plan.meals) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              meal.time.isEmpty ? meal.name : '${meal.name} · ${meal.time}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            for (final item in meal.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('•  $item', style: const TextStyle(fontSize: 15, height: 1.45)),
              ),
            if (meal.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  meal.notes,
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
          if (plan.avoid.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const Text('Best avoided', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final item in plan.avoid)
                  Chip(label: Text(item), visualDensity: VisualDensity.compact),
              ],
            ),
          ],
          if (plan.notes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(plan.notes, style: const TextStyle(fontSize: 15, height: 1.5)),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

// ---- Medicines ------------------------------------------------------------

class _Medicines extends StatelessWidget {
  const _Medicines({required this.items});

  final List<CareMedication> items;

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
      // stretch, not the default centre: without it each row shrinks to the
      // width of its own text and floats in the middle, so a list of medicines
      // has a different left edge on every line and nothing to read down.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    items[i].title,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i].scheduleLabel,
                    style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ],
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

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        child: Column(
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 34, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'No meals logged yet',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Photos of what you eat help your dietician give better advice.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 208,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final log = items[i];
          return SizedBox(
            width: 196,
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 124,
                    width: double.infinity,
                    child: log.photoUrl != null
                        ? AuthedImage(path: log.photoUrl!, fit: BoxFit.cover)
                        : Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.restaurant_menu_rounded,
                              size: 30,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [_when(log.createdAt), _meal(log.mealType)]
                              .where((s) => s.isNotEmpty)
                              .join(', '),
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          log.note.isNotEmpty ? log.note : _meal(log.mealType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text, this.action, this.onAction});

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurface),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
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
    final critical = profile.riskBand == 'critical' || profile.riskBand == 'high';
    final fg = critical ? AppColors.danger : AppColors.warning;
    final bg = critical ? AppColors.dangerBgOn(context) : AppColors.warningBgOn(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: fg),
          const SizedBox(width: 5),
          Text(
            profile.riskLabel,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

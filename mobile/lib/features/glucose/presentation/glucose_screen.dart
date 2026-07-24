import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/empty_view.dart';
import '../../../shared/widgets/error_view.dart';
import '../data/glucose_repository.dart';
import 'glucose_providers.dart';
import 'log_glucose_sheet.dart';
import 'widgets/glucose_reading_tile.dart';
import 'widgets/glucose_stats_row.dart';
import 'widgets/glucose_trend_chart.dart';

/// The "Glucose" tab of the Track screen.
class GlucoseScreen extends ConsumerWidget {
  const GlucoseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readingsAsync = ref.watch(glucoseReadingsProvider);
    final trendsAsync = ref.watch(glucoseTrendsProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLogGlucoseSheet(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.glucoseLogReading),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(glucoseReadingsProvider);
          ref.invalidate(glucoseTrendsProvider);
          await Future.wait([
            ref.read(glucoseReadingsProvider.future),
            ref.read(glucoseTrendsProvider.future),
          ]);
        },
        child: readingsAsync.when(
          loading: () => ListView(
            children: const [
              SizedBox(height: 240, child: Center(child: CircularProgressIndicator())),
            ],
          ),
          error: (error, _) => ListView(
            children: [
              SizedBox(
                height: 400,
                child: ErrorView(error: error, onRetry: () => ref.invalidate(glucoseReadingsProvider)),
              ),
            ],
          ),
          data: (paged) {
            if (paged.items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: 500,
                    child: EmptyView(
                      icon: Icons.bloodtype_outlined,
                      title: l10n.glucoseEmptyTitle,
                      body: l10n.glucoseEmptyBody,
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xxl,
              ),
              children: [
                trendsAsync.when(
                  loading: () => const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (trends) {
                    if (trends.series.length < 2) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.glucoseTrend, style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: AppSpacing.sm),
                        AppCard(child: GlucoseTrendChart(trends: trends)),
                        const SizedBox(height: AppSpacing.md),
                        GlucoseStatsRow(stats: trends.stats),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                    );
                  },
                ),
                Text(l10n.glucoseRecentReadings, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                for (final reading in paged.items)
                  GlucoseReadingTile(
                    reading: reading,
                    onDelete: () async {
                      await ref.read(glucoseRepositoryProvider).deleteReading(reading.id);
                      ref.invalidate(glucoseReadingsProvider);
                      ref.invalidate(glucoseTrendsProvider);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/core_providers.dart';

/// What patients have said about the clinic and about the app.
///
/// Kept out of the clinical-alert queue on purpose: a five-star note and a
/// hypo report must never share a list, or the list that matters gets skimmed.
final _feedbackProvider = FutureProvider.autoDispose<List<_Entry>>((ref) async {
  final data = await ref.read(apiClientProvider).getJson('/feedback', query: {'limit': 100});
  final items = (data['items'] as List?) ?? const [];
  return items.map((e) => _Entry.fromJson(e as Map<String, dynamic>)).toList();
});

class FeedbackInboxScreen extends ConsumerStatefulWidget {
  const FeedbackInboxScreen({super.key});

  @override
  ConsumerState<FeedbackInboxScreen> createState() => _FeedbackInboxScreenState();
}

class _FeedbackInboxScreenState extends ConsumerState<FeedbackInboxScreen> {
  String? _about;

  static const _filters = [(null, 'All'), ('clinic', 'The clinic'), ('app', 'The app')];

  Future<void> _markReviewed(_Entry entry) async {
    await ref.read(apiClientProvider).postJson('/feedback/${entry.id}/reviewed');
    ref.invalidate(_feedbackProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(_feedbackProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patient feedback'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                itemCount: _filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, i) {
                  final (value, label) = _filters[i];
                  return ChoiceChip(
                    label: Text(label),
                    selected: _about == value,
                    onSelected: (_) => setState(() => _about = value),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_feedbackProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => ListView(
            children: [
              const SizedBox(height: 120),
              const Center(child: Text('Could not load feedback')),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(_feedbackProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          data: (all) {
            final items = _about == null ? all : all.where((e) => e.about == _about).toList();
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Nothing here yet',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(
                      'Feedback patients send from their profile appears here.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _FeedbackCard(
                entry: items[i],
                onReviewed: () => _markReviewed(items[i]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.entry, required this.onReviewed});

  final _Entry entry;
  final VoidCallback onReviewed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isClinic = entry.about == 'clinic';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: entry.reviewed ? scheme.outlineVariant : AppColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isClinic ? Icons.local_hospital_rounded : Icons.phone_android_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                isClinic ? 'The clinic' : 'The app',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              if (entry.rating != null)
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      Icon(
                        entry.rating! >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 16,
                        color: entry.rating! >= i ? AppColors.warning : scheme.outline,
                      ),
                  ],
                ),
            ],
          ),
          if (entry.message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(entry.message, style: const TextStyle(fontSize: 15, height: 1.45)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${entry.patientName ?? 'Patient'} · ${DateFormat('d MMM, h:mm a').format(entry.createdAt.toLocal())}',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
              if (entry.reviewed)
                Icon(Icons.check_circle_rounded, size: 18, color: AppColors.primary)
              else
                TextButton(onPressed: onReviewed, child: const Text('Mark reviewed')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Entry {
  _Entry({
    required this.id,
    required this.about,
    required this.rating,
    required this.message,
    required this.reviewed,
    required this.createdAt,
    required this.patientName,
  });

  final String id;
  final String about;
  final int? rating;
  final String message;
  final bool reviewed;
  final DateTime createdAt;
  final String? patientName;

  factory _Entry.fromJson(Map<String, dynamic> json) => _Entry(
    id: json['id'].toString(),
    about: json['about'] as String? ?? 'clinic',
    rating: (json['rating'] as num?)?.toInt(),
    message: json['message'] as String? ?? '',
    reviewed: json['reviewed'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
    patientName: json['patientName'] as String?,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';

/// What patients have said about the clinic and about the app.
///
/// Kept out of the clinical-alert queue on purpose: a five-star note and a
/// hypo report must never share a list, or the list that matters gets skimmed.
///
/// Read-only by design. Feedback is written in the patient panel and read here;
/// the server enforces that split, so a clinician cannot post one and a patient
/// cannot read anyone else's.
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
    final user = ref.watch(authControllerProvider).user;
    final async = ref.watch(_feedbackProvider);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _BrandHeader(name: user?.name ?? '', avatarUrl: user?.avatarUrl),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(_feedbackProvider),
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => ListView(
                    children: [
                      const SizedBox(height: 140),
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
                    final items = _about == null
                        ? all
                        : all.where((e) => e.about == _about).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      children: [
                        const Text(
                          'Patient Feedback',
                          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.15),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Review and manage recent experiences reported by your patients.',
                          style: TextStyle(fontSize: 15.5, height: 1.4, color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Row(
                          children: [
                            for (final (value, label) in _filters) ...[
                              _FilterChip(
                                label: label,
                                selected: _about == value,
                                onTap: () => setState(() => _about = value),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        if (items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 70),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.rate_review_outlined,
                                  size: 50,
                                  color: scheme.outlineVariant,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  _about == null ? 'Nothing here yet' : 'Nothing under this filter',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Feedback patients send from their profile appears here.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          )
                        else
                          for (final entry in items)
                            _FeedbackCard(entry: entry, onReviewed: () => _markReviewed(entry)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: Icon(Icons.arrow_back_rounded, color: scheme.onSurface),
          ),
          Image.asset(
            'assets/brand/medpin_emblem.png',
            height: 28,
            errorBuilder: (_, _, _) =>
                Icon(Icons.rate_review_rounded, size: 24, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 8),
          Text(
            'MedPin',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
          ),
          const Spacer(),
          UserAvatar(name: name, avatarUrl: avatarUrl, accent: AppColors.accentOn(context), size: 38),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.infoBgOn(context),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.primary,
            ),
          ),
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
    final unread = !entry.reviewed;
    final ink = unread ? scheme.onSurface : scheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The unread marker. A stripe rather than a dot: it runs the height
            // of the card, so a long list shows at a glance how much is still
            // outstanding without reading a word of it.
            Container(width: 5, color: unread ? AppColors.primary : Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.heading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: ink,
                            ),
                          ),
                        ),
                        // Stars only when the patient actually gave a rating.
                        // Five hollow stars over an unrated note would read as
                        // one star — the worst score they never gave.
                        if (entry.rating != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 1; i <= 5; i++)
                                Icon(
                                  entry.rating! >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                                  size: 20,
                                  color: unread ? AppColors.primary : scheme.onSurfaceVariant,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    if (entry.message.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        entry.message,
                        style: TextStyle(fontSize: 15, height: 1.45, color: ink),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.7)),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Icon(Icons.person_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            // The subject is named here rather than on its own
                            // row: under "All" the doctor otherwise cannot tell
                            // a complaint about care from one about the app.
                            '${entry.patientName ?? 'Patient'} · ${entry.aboutLabel}'
                            '${entry.createdAt != null ? ' · ${DateFormat('d MMM').format(entry.createdAt!.toLocal())}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        if (unread)
                          Material(
                            color: AppColors.infoBgOn(context),
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: onReviewed,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle_outline_rounded,
                                        size: 17, color: AppColors.accentOn(context)),
                                    SizedBox(width: 6),
                                    Text(
                                      'Mark reviewed',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accentOn(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.done_all_rounded, size: 17, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'Reviewed',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
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
  final DateTime? createdAt;
  final String? patientName;

  String get aboutLabel => about == 'app' ? 'The app' : 'The clinic';

  /// The card's headline. Taken from the patient's own opening words rather
  /// than a separate subject field — asking for a title before they can say
  /// what happened is a second hurdle in front of a complaint, and the
  /// first clause is almost always what the note is about anyway.
  String get heading {
    final text = message.trim();
    if (text.isEmpty) return rating != null ? 'Rated $rating out of 5' : aboutLabel;

    final stop = text.indexOf(RegExp(r'[.!?\n]'));
    var head = stop > 0 ? text.substring(0, stop) : text;
    if (head.length > 42) head = '${head.substring(0, 42).trimRight()}…';
    return head;
  }

  factory _Entry.fromJson(Map<String, dynamic> json) => _Entry(
    id: json['id'].toString(),
    about: json['about'] as String? ?? 'clinic',
    rating: (json['rating'] as num?)?.toInt(),
    message: json['message'] as String? ?? '',
    reviewed: json['reviewed'] as bool? ?? false,
    createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    patientName: json['patientName'] as String?,
  );
}

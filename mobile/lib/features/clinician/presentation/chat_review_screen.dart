import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/network/api_exception.dart';
import '../data/clinician_repository.dart';
import '../domain/chat_review.dart';
import 'clinician_providers.dart';
import 'widgets/clinician_visuals.dart';

/// Assistant-conversation review: the threads the assistant or a patient
/// flagged for a clinician to check.
class ChatReviewScreen extends ConsumerStatefulWidget {
  const ChatReviewScreen({super.key, this.initialTab});

  /// `nutrition` | `all` | `flagged`. Null opens on the flagged queue.
  final String? initialTab;

  @override
  ConsumerState<ChatReviewScreen> createState() => _ChatReviewScreenState();
}

/// The two views of the review queue. (Nutrition conversations now have their
/// own top-level Nutrition tab, so they are no longer a filter here — chat
/// review is purely the clinical care threads.)
enum _ReviewTab { flagged, all }

class _ChatReviewScreenState extends ConsumerState<ChatReviewScreen> {
  late _ReviewTab _tab = widget.initialTab == 'all' ? _ReviewTab.all : _ReviewTab.flagged;

  ChatReviewQuery get _query => (
    flagged: _tab == _ReviewTab.flagged,
    urgency: null,
    kind: 'care',
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(chatReviewProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat review'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final (tab, label) in const [
                  (_ReviewTab.flagged, 'Flagged'),
                  (_ReviewTab.all, 'All chats'),
                ]) ...[
                  ChoiceChip(
                    label: Text(label),
                    selected: _tab == tab,
                    onSelected: (_) => setState(() => _tab = tab),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(chatReviewProvider(_query)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load conversations'),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed:
                          () => ref.invalidate(chatReviewProvider(_query)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
          data: (paged) {
            if (paged.items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  Icon(
                    Icons.forum_outlined,
                    size: 56,
                    color: scheme.outlineVariant,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Center(
                    child: Text(
                      switch (_tab) {
                        _ReviewTab.flagged => 'No flagged conversations',
                        _ReviewTab.all => 'No conversations',
                      },
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: paged.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder:
                  (context, i) => _SessionRow(
                    session: paged.items[i],
                    onTap:
                        () => context.push(
                          '/clinician/chat-review/${paged.items[i].id}',
                        ),
                    onCleared: () => ref.invalidate(chatReviewProvider(_query)),
                  ),
            );
          },
        ),
      ),
    );
  }
}

class _SessionRow extends ConsumerWidget {
  const _SessionRow({required this.session, required this.onTap, required this.onCleared});

  final ChatReviewSession session;
  final VoidCallback onTap;

  /// Called after the flag is cleared, so the list can refetch.
  final VoidCallback onCleared;

  /// Clears the review flag without opening the conversation.
  ///
  /// The doctor could only unflag from inside a thread, so a queue of old
  /// flags could only be cleared by opening every one of them — and a queue
  /// nobody can clear stops being read at all, which is the failure mode that
  /// matters when the next flag is a real emergency.
  Future<void> _clearFlag(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(clinicianRepositoryProvider).markReviewed(session.id);
      onCleared();
      messenger.showSnackBar(const SnackBar(content: Text('Flag cleared')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    final color = AppColors.forUrgencyOn(context, s.highestUrgency);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.patientName ?? 'Patient',
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (s.highestUrgency != 'routine')
                  MiniPill(label: s.highestUrgency.toUpperCase(), color: color),
                if (s.flaggedForReview) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.flag_rounded,
                    size: 16,
                    color: AppColors.warningOn(context),
                  ),
                ],
                // How many messages here nobody at the clinic has opened.
                // Without it the doctor had to open every row to find which
                // ones were actually new.
                if (s.unreadCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentOn(context),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${s.unreadCount} new',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(
              s.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 13,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 3),
                Text(
                  '${s.messageCount}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                if (s.lastMessageAt != null)
                  Text(
                    DateFormat('d MMM, h:mm a').format(s.lastMessageAt!),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                if (s.flaggedForReview)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    onPressed: () => _clearFlag(context, ref),
                    icon: const Icon(Icons.flag_outlined, size: 15),
                    label: const Text(
                      'Clear flag',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  )
                else if (s.reviewedAt != null)
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 13,
                        color: AppColors.successOn(context),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Reviewed',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

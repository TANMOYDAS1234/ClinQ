import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/chat_review.dart';
import 'clinician_providers.dart';
import 'widgets/clinician_visuals.dart';

/// Assistant-conversation review: the threads the assistant or a patient
/// flagged for a clinician to check.
class ChatReviewScreen extends ConsumerStatefulWidget {
  const ChatReviewScreen({super.key});

  @override
  ConsumerState<ChatReviewScreen> createState() => _ChatReviewScreenState();
}

/// The three views of the review queue. One field rather than two booleans:
/// as a pair they allowed "flagged *and* nutrition", and the nutrition case
/// only ever cleared the flag — so the Nutrition tab sent the same query as
/// All chats and listed every clinical thread alongside the diet ones.
enum _ReviewTab { flagged, all, nutrition }

class _ChatReviewScreenState extends ConsumerState<ChatReviewScreen> {
  _ReviewTab _tab = _ReviewTab.flagged;

  /// Nutrition threads are a separate conversation with the dietician, so the
  /// clinical tabs exclude them: a diet question is not a review item.
  ChatReviewQuery get _query => (
    flagged: _tab == _ReviewTab.flagged,
    urgency: null,
    kind: _tab == _ReviewTab.nutrition ? 'nutrition' : 'care',
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
                  (_ReviewTab.nutrition, 'Nutrition'),
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
                        _ReviewTab.nutrition => 'No nutrition conversations',
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
                  ),
            );
          },
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onTap});

  final ChatReviewSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
                if (s.reviewedAt != null)
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

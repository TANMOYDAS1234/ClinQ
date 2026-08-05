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

class _ChatReviewScreenState extends ConsumerState<ChatReviewScreen> {
  bool _flaggedOnly = true;

  /// Nutrition threads are a separate conversation with the dietician. The
  /// doctor can read them, but they should not be mixed into the flagged queue
  /// of clinical chats — a diet question is not a review item.
  bool _nutritionOnly = false;

  ChatReviewQuery get _query => (flagged: _flaggedOnly && !_nutritionOnly, urgency: null);

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
                ChoiceChip(label: const Text('Flagged'), selected: _flaggedOnly, onSelected: (_) => setState(() => _flaggedOnly = true)),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(label: const Text('All chats'), selected: !_flaggedOnly && !_nutritionOnly, onSelected: (_) => setState(() { _flaggedOnly = false; _nutritionOnly = false; })),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(label: const Text('Nutrition'), selected: _nutritionOnly, onSelected: (_) => setState(() { _nutritionOnly = true; _flaggedOnly = false; })),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(chatReviewProvider(_query)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load conversations'),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(onPressed: () => ref.invalidate(chatReviewProvider(_query)), child: const Text('Retry')),
              ],
            ),
          ),
          data: (paged) {
            if (paged.items.isEmpty) {
              return ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                  Icon(Icons.forum_outlined, size: 56, color: scheme.outlineVariant),
                  const SizedBox(height: AppSpacing.md),
                  Center(child: Text(_flaggedOnly ? 'No flagged conversations' : 'No conversations', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: paged.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _SessionRow(
                session: paged.items[i],
                onTap: () => context.push('/clinician/chat-review/${paged.items[i].id}'),
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
    final color = AppColors.forUrgency(s.highestUrgency);

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
                Expanded(child: Text(s.patientName ?? 'Patient', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
                if (s.highestUrgency != 'routine') MiniPill(label: s.highestUrgency.toUpperCase(), color: color),
                if (s.flaggedForReview) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.flag_rounded, size: 16, color: AppColors.warning),
                ],
              ],
            ),
            const SizedBox(height: 3),
            Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 3),
                Text('${s.messageCount}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 10),
                if (s.lastMessageAt != null)
                  Text(DateFormat('d MMM, h:mm a').format(s.lastMessageAt!), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const Spacer(),
                if (s.reviewedAt != null)
                  Row(children: [
                    const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.success),
                    const SizedBox(width: 3),
                    Text('Reviewed', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

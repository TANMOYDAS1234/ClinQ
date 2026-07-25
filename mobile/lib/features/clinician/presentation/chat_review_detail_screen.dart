import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/markdown_text.dart';
import '../data/clinician_repository.dart';
import '../domain/chat_review.dart';
import 'clinician_providers.dart';
import 'widgets/clinician_visuals.dart';

/// One conversation, with the safety audit trail on every assistant reply —
/// the triage verdict, whether it was rule-driven, its grounding citations and
/// whether it fell back to a scripted answer.
class ChatReviewDetailScreen extends ConsumerWidget {
  const ChatReviewDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chatReviewDetailProvider(sessionId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
        actions: [
          async.maybeWhen(
            data: (d) => d.session.flaggedForReview
                ? Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: TextButton.icon(
                      onPressed: () => _markReviewed(context, ref),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Reviewed'),
                    ),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load conversation'),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(onPressed: () => ref.invalidate(chatReviewDetailProvider(sessionId)), child: const Text('Retry')),
            ],
          ),
        ),
        data: (detail) => Column(
          children: [
            _SessionHeader(session: detail.session),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: detail.messages.length,
                itemBuilder: (context, i) => _MessageBubble(message: detail.messages[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markReviewed(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(clinicianRepositoryProvider).markReviewed(sessionId);
      ref.invalidate(chatReviewDetailProvider(sessionId));
      ref.invalidate(chatReviewProvider((flagged: true, urgency: null)));
      messenger.showSnackBar(const SnackBar(content: Text('Marked as reviewed')));
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update. Please try again.')));
    }
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({required this.session});
  final ChatReviewSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    final color = AppColors.forUrgency(s.highestUrgency);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: scheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.patientName ?? 'Patient', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              MiniPill(label: s.highestUrgency.toUpperCase(), color: color, filled: s.highestUrgency == 'emergency'),
            ],
          ),
          const SizedBox(height: 2),
          Text(s.title, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});
  final ChatReviewMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final m = message;
    final isUser = m.isUser;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isUser ? AppColors.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Icon(isUser ? Icons.person_rounded : Icons.smart_toy_outlined, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(isUser ? 'Patient' : 'Assistant', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
              if (m.flaggedByPatient) ...[
                const SizedBox(width: 6),
                const Icon(Icons.flag_rounded, size: 14, color: AppColors.warning),
                const Text(' reported', style: TextStyle(fontSize: 11, color: AppColors.warning)),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(14)),
            child: isUser
                ? Text(m.content, style: const TextStyle(fontSize: 14.5, height: 1.4))
                : MarkdownText(
                    data: m.content,
                    selectable: true,
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: scheme.onSurface),
                  ),
          ),
          // Audit chips for assistant replies.
          if (!isUser) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (m.urgency != 'routine') _chip(m.urgency.toUpperCase(), AppColors.forUrgency(m.urgency)),
                if (m.ruleDriven) _chip('rule-driven', AppColors.primary),
                if (m.isFallback) _chip('fallback', AppColors.warning),
                if (m.citations.isNotEmpty) _chip('${m.citations.length} source${m.citations.length == 1 ? '' : 's'}', const Color(0xFF6B7280)),
                if (m.latencyMs != null) _chip('${(m.latencyMs! / 1000).toStringAsFixed(1)}s', const Color(0xFF6B7280)),
              ],
            ),
            if (m.citations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('Sources: ${m.citations.join(', ')}', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
    child: Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
  );
}

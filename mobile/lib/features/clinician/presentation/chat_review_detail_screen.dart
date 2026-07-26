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
            // Reply from inside the conversation. Reading the exchange and
            // answering it are one action for a doctor, so making them two
            // screens only costs time at the moment a patient is waiting.
            if (detail.session.patientId != null)
              _ClinicianComposer(
                patientId: detail.session.patientId!,
                onSent: () => ref.invalidate(chatReviewDetailProvider(sessionId)),
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

/// Bottom composer on the doctor's view of a conversation.
///
/// Posts as `role: 'clinician'`, so the words land in the patient's own
/// Health Assistant thread rather than a parallel inbox.
class _ClinicianComposer extends ConsumerStatefulWidget {
  const _ClinicianComposer({required this.patientId, required this.onSent});

  final String patientId;
  final VoidCallback onSent;

  @override
  ConsumerState<_ClinicianComposer> createState() => _ClinicianComposerState();
}

class _ClinicianComposerState extends ConsumerState<_ClinicianComposer> {
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(clinicianRepositoryProvider)
          .messagePatient(patientId: widget.patientId, content: text);
      _controller.clear();
      widget.onSent();
      messenger.showSnackBar(const SnackBar(content: Text('Sent to the patient')));
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Reply to this patient…',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sending ? null : _send,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Center(
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 21),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    final isClinician = m.isClinician;
    // The clinic's replies sit on the same side as the assistant, matching what
    // the patient sees: one continuous conversation rather than messages
    // hopping sides. Who spoke is carried by the label, not the alignment.
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = isUser
        ? AppColors.primary.withValues(alpha: 0.12)
        : isClinician
        ? AppColors.primary.withValues(alpha: 0.22)
        : scheme.surfaceContainerHighest;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Icon(
                isUser
                    ? Icons.person_rounded
                    : isClinician
                    ? Icons.medical_information_rounded
                    : Icons.smart_toy_outlined,
                size: 15,
                color: isClinician ? AppColors.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                isUser
                    ? 'Patient'
                    : isClinician
                    ? 'You / clinic'
                    : 'Assistant',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isClinician ? AppColors.primary : scheme.onSurfaceVariant,
                ),
              ),
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
            child: isUser || isClinician
                ? Text(m.content, style: const TextStyle(fontSize: 14.5, height: 1.4))
                : MarkdownText(
                    data: m.content,
                    selectable: true,
                    style: TextStyle(fontSize: 14.5, height: 1.4, color: scheme.onSurface),
                  ),
          ),
          // Audit chips describe an assistant answer — a human reply has no
          // triage verdict, grounding or latency to account for.
          if (!isUser && !isClinician) ...[
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

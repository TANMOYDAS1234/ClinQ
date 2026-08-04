import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/dietician_repository.dart';
import '../domain/diet_models.dart';
import 'dietician_providers.dart';

/// The dietician's side of the patient's care conversation. The dietician's
/// replies land in the same thread the patient reads (as the doctor's do), so
/// there is a single food + care conversation, never two half-conversations.
class DieticianChatScreen extends ConsumerStatefulWidget {
  const DieticianChatScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<DieticianChatScreen> createState() => _DieticianChatScreenState();
}

class _DieticianChatScreenState extends ConsumerState<DieticianChatScreen> {
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
      await ref.read(dieticianRepositoryProvider).sendMessage(widget.patientId, content: text);
      _controller.clear();
      ref.invalidate(dietThreadProvider(widget.patientId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietThreadProvider(widget.patientId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.patientName ?? 'Patient', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('Nutrition chat', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load the conversation'),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(onPressed: () => ref.invalidate(dietThreadProvider(widget.patientId)), child: const Text('Retry')),
                  ],
                ),
              ),
              data: (messages) {
                final shown = messages.where((m) => m.role != 'system').toList();
                if (shown.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text('Say hello and share your first food guidance.',
                          textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => _Bubble(message: shown[shown.length - 1 - i]),
                );
              },
            ),
          ),
          _Composer(controller: _controller, sending: _sending, onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final DietMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.fromDietician;
    final label = switch (message.role) {
      'dietician' => 'You',
      'user' => 'Patient',
      'clinician' => 'Doctor',
      'assistant' => 'Assistant',
      _ => message.senderName ?? '',
    };
    final bg = mine ? AppColors.primary.withValues(alpha: 0.12) : scheme.surfaceContainerHighest;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 2),
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mine ? AppColors.primary : scheme.onSurfaceVariant)),
          ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.content.isNotEmpty)
                  Text(message.content, style: const TextStyle(fontSize: 15, height: 1.35)),
                if (message.attachments.isNotEmpty) ...[
                  if (message.content.isNotEmpty) const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file_rounded, size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('${message.attachments.length} attachment${message.attachments.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
                if (message.createdAt != null) ...[
                  const SizedBox(height: 3),
                  Text(DateFormat('d MMM, h:mm a').format(message.createdAt!),
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 8),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Recommend a meal or reply…',
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 46,
              height: 46,
              child: FilledButton(
                onPressed: sending ? null : onSend,
                style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder(), backgroundColor: AppColors.primary),
                child: sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

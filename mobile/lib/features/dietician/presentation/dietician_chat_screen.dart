import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/chat_background.dart';
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
      // The same wallpaper the patient and the doctor see. A different backdrop
      // per panel would read as three products showing three different threads.
      body: ChatBackground(
        child: Column(
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

    // Matches the patient's and doctor's bubbles: a badge and a name on every
    // received turn, so a thread carrying an AI, a doctor and a dietician never
    // leaves the reader guessing which of them said something.
    final (icon, label) = switch (message.role) {
      'user' => (Icons.person_rounded, message.senderName ?? 'Patient'),
      'clinician' => (Icons.medical_information_rounded, message.senderName ?? 'Doctor'),
      'assistant' => (Icons.smart_toy_rounded, 'AI Assistant'),
      _ => (Icons.restaurant_rounded, message.senderName ?? 'Dietician'),
    };

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (mine)
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 5),
                child: Text(
                  'You',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 14, color: AppColors.primary),
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: message.role == 'clinician'
                              ? AppColors.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: mine ? AppColors.primary : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(mine ? 20 : 6),
                  bottomRight: Radius.circular(mine ? 6 : 20),
                ),
                border: mine
                    ? null
                    : Border.all(color: scheme.outlineVariant.withValues(alpha: 0.20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.content.isNotEmpty)
                    Text(
                      message.content,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        color: mine ? Colors.white : scheme.onSurface,
                      ),
                    ),
                  if (message.attachments.isNotEmpty) ...[
                    if (message.content.isNotEmpty) const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.attach_file_rounded,
                          size: 15,
                          color: mine ? Colors.white70 : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${message.attachments.length} attachment'
                          '${message.attachments.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: mine ? Colors.white70 : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (message.createdAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      DateFormat('h:mm a').format(message.createdAt!),
                      style: TextStyle(
                        fontSize: 11,
                        color: mine ? Colors.white70 : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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

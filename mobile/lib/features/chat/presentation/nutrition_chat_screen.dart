import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/data/upload_repository.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/widgets/chat_background.dart';
import '../domain/chat_message.dart';
import 'widgets/chat_message_bubble.dart';

/// The patient's side of the dietician conversation.
///
/// Separate from the Assistant thread so diet coaching and clinical questions
/// do not interleave — but the server runs the *same* triage on anything sent
/// here. Which inbox a patient happens to pick must never decide whether a
/// worrying symptom reaches the clinic.
final nutritionThreadProvider = FutureProvider.autoDispose<List<ChatMessage>>((ref) async {
  final json = await ref.read(apiClientProvider).getJson('/chat/nutrition');
  final items = (json['items'] as List?) ?? const [];
  return items.whereType<Map<String, dynamic>>().map(ChatMessage.fromJson).toList();
});

class NutritionChatScreen extends ConsumerStatefulWidget {
  const NutritionChatScreen({super.key});

  @override
  ConsumerState<NutritionChatScreen> createState() => _NutritionChatScreenState();
}

class _NutritionChatScreenState extends ConsumerState<NutritionChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Sends a meal photo. Server-side this also becomes a food-log entry, so the
  /// patient never has to log the same meal twice — showing it to the dietician
  /// and recording it are the same act.
  Future<void> _sendPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
    if (file == null) return;

    setState(() => _sending = true);
    try {
      final asset = await ref.read(uploadRepositoryProvider).uploadImage(
        path: file.path,
        filename: file.name,
      );
      await ref.read(apiClientProvider).postJson(
        '/chat/nutrition',
        body: {
          'content': _controller.text.trim(),
          'attachments': [asset.id],
        },
      );
      _controller.clear();
      ref.invalidate(nutritionThreadProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      final res = await ref.read(apiClientProvider).postJson(
        '/chat/nutrition',
        body: {'content': text},
      );
      _controller.clear();
      // Refetch rather than append: the server may have added a plan-bound
      // assistant turn after the patient's, and re-reading is the only way to
      // get both in the right order without guessing at sequence numbers.
      ref.invalidate(nutritionThreadProvider);

      // The server triages this thread exactly like the care thread. If it
      // escalated, say so here rather than letting the patient assume a
      // dietician will read it in the morning.
      final urgency = (res['triage'] as Map?)?['urgency']?.toString();
      if (urgency == 'emergency' || urgency == 'urgent') {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 6),
            content: Text(
              urgency == 'emergency'
                  ? 'This looks urgent — the clinic has been alerted. If you feel unwell now, call them.'
                  : 'The clinic has been alerted about this message.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(nutritionThreadProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your dietician',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            Text(
              'Food and nutrition',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          // The log still exists as a list — scrolling back weeks through a
          // conversation to find one meal is not a search.
          IconButton(
            tooltip: 'Meal history',
            onPressed: () => context.push('/food-log/history'),
            icon: const Icon(Icons.photo_library_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
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
                      OutlinedButton(
                        onPressed: () => ref.invalidate(nutritionThreadProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (messages) {
                  final shown = messages.where((m) => m.role != 'system').toList();
                  if (shown.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.restaurant_rounded,
                              size: 46,
                              color: scheme.outlineVariant,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            const Text(
                              'No messages yet',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ask your dietician about food, portions or your plan.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: shown.length,
                    itemBuilder: (context, i) =>
                        ChatMessageBubble(message: shown[shown.length - 1 - i]),
                  );
                },
              ),
            ),
            _Composer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
              onAttach: _sendPhoto,
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Send a meal photo',
              onPressed: sending ? null : onAttach,
              icon: Icon(Icons.add_circle_outline_rounded, size: 27, color: AppColors.primary),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message your dietician…',
                  filled: true,
                  fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(26),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 22, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

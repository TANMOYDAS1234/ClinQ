import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/providers/core_providers.dart';
import '../../../shared/widgets/chat_background.dart';
import '../domain/chat_message.dart';
import 'widgets/care_composer.dart';
import 'widgets/jump_to_latest.dart';
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

  /// The list is reversed, so "at the latest" is offset 0.
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final away = _scroll.offset > 220;
    if (away != _showJump) setState(() => _showJump = away);
  }

  void _toLatest() => _scroll.animateTo(
    0,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Posts an already-uploaded attachment. A photo sent here also becomes a
  /// food-log entry server-side, so the patient never logs the same meal twice.
  Future<void> _sendAttachment(String assetId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiClientProvider).postJson(
        '/chat/nutrition',
        body: {
          'content': _controller.text.trim(),
          'attachments': [assetId],
        },
      );
      _controller.clear();
      ref.invalidate(nutritionThreadProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
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
            Align(
              alignment: Alignment.centerRight,
              child: JumpToLatest(visible: _showJump, onTap: _toLatest),
            ),
            CareComposer(
              controller: _controller,
              hint: 'Message your dietician…',
              sending: _sending,
              onSend: _send,
              onSendAttachment: _sendAttachment,
            ),
          ],
        ),
      ),
    );
  }
}

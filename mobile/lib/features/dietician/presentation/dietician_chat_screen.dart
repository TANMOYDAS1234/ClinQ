import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/chat_background.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/presentation/widgets/care_composer.dart';
import '../../chat/presentation/widgets/chat_attachment_thumbs.dart';
import '../../chat/presentation/widgets/chat_document_card.dart';
import '../../chat/presentation/widgets/voice_note_player.dart';
import '../../chat/presentation/widgets/jump_to_latest.dart';
import '../data/dietician_repository.dart';
import '../domain/diet_models.dart';
import 'dietician_providers.dart';

/// The dietician's side of the patient's care conversation. The dietician's
/// replies land in the same thread the patient reads (as the doctor's do), so
/// there is a single food + care conversation, never two half-conversations.
class DieticianChatScreen extends ConsumerStatefulWidget {
  const DieticianChatScreen({
    super.key,
    required this.patientId,
    this.patientName,
  });

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<DieticianChatScreen> createState() =>
      _DieticianChatScreenState();
}

class _DieticianChatScreenState extends ConsumerState<DieticianChatScreen> {
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

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(dieticianRepositoryProvider)
          .sendMessage(widget.patientId, content: text);
      _controller.clear();
      ref.invalidate(dietThreadProvider(widget.patientId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Posts an already-uploaded photo, document or voice note.
  Future<void> _sendAttachment(String assetId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(dieticianRepositoryProvider)
          .sendMessage(
            widget.patientId,
            content: _controller.text.trim(),
            attachments: [assetId],
          );
      _controller.clear();
      ref.invalidate(dietThreadProvider(widget.patientId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietThreadProvider(widget.patientId));
    final overview =
        ref.watch(dietOverviewProvider(widget.patientId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
              name: overview?.name ?? widget.patientName ?? '',
              avatarUrl: overview?.avatarUrl,
              accent: AppColors.primary,
              size: 38,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overview?.name ?? widget.patientName ?? 'Patient',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Nutrition chat',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (overview?.phone.isNotEmpty == true)
            IconButton(
              tooltip: 'Call patient',
              onPressed:
                  () => launchUrl(Uri(scheme: 'tel', path: overview!.phone)),
              icon: const Icon(Icons.call_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      // The same wallpaper the patient and the doctor see. A different backdrop
      // per panel would read as three products showing three different threads.
      body: ChatBackground(
        child: Column(
          children: [
            Expanded(
              // Floats over the thread rather than taking a row of its own — in
              // the column it covered the newest message instead of hovering
              // above it. See the patient's side of this thread.
              child: Stack(
                children: [
                  async.when(
                    loading:
                        () => const Center(child: CircularProgressIndicator()),
                    error:
                        (_, _) => Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Could not load the conversation'),
                              const SizedBox(height: AppSpacing.sm),
                              OutlinedButton(
                                onPressed:
                                    () => ref.invalidate(
                                      dietThreadProvider(widget.patientId),
                                    ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                    data: (messages) {
                      final shown =
                          messages.where((m) => m.role != 'system').toList();
                      if (shown.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Text(
                              'Say hello and share your first food guidance.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md + 48,
                        ),
                        itemCount: shown.length,
                        itemBuilder:
                            (context, i) =>
                                _Bubble(message: shown[shown.length - 1 - i]),
                      );
                    },
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: JumpToLatest(visible: _showJump, onTap: _toLatest),
                  ),
                ],
              ),
            ),
            CareComposer(
              controller: _controller,
              hint: 'Recommend a meal or reply…',
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
      // No label on the patient's own turns: in a thread with one patient
      // in it, naming them on every message is noise.
      'user' => (Icons.person_rounded, ''),
      'clinician' => (
        Icons.medical_information_rounded,
        message.senderName ?? 'Doctor',
      ),
      'assistant' => (Icons.smart_toy_rounded, 'AI Assistant'),
      _ => (Icons.restaurant_rounded, message.senderName ?? 'Dietician'),
    };

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
            // Nothing above the patient's own bubbles: in a thread with one
            // patient in it, an avatar and a name on every message is furniture.
            // The dietician knows who they are talking to.
            else if (message.role != 'user')
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
                          color:
                              message.role == 'clinician'
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
                border:
                    mine
                        ? null
                        : Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.20),
                        ),
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
                  // The meal itself, not a count of it. This is the thread the
                  // patient photographs their food into, so "1 attachment" was
                  // the dietician being told a picture existed somewhere.
                  if (message.hasAttachments) ...[
                    if (message.content.isNotEmpty) const SizedBox(height: 8),
                    if (message.imagePaths.isNotEmpty)
                      ChatAttachmentThumbs(paths: message.imagePaths),
                    for (final note in message.voiceNotes)
                      VoiceNotePlayer(note: note, onDark: mine),
                    for (final doc in message.documents)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ChatDocumentCard(doc: doc, onDark: mine),
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

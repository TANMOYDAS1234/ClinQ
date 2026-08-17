import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/chat_background.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../chat/data/chat_repository.dart';
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

  /// The message the dietician is quoting in their next reply.
  DietMessage? _replyingTo;

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
    final replyTo = _replyingTo?.id;
    try {
      await ref
          .read(dieticianRepositoryProvider)
          .sendMessage(widget.patientId, content: text, replyTo: replyTo);
      _controller.clear();
      if (mounted) setState(() => _replyingTo = null);
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
            replyTo: _replyingTo?.id,
          );
      _controller.clear();
      if (mounted) setState(() => _replyingTo = null);
      ref.invalidate(dietThreadProvider(widget.patientId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Pin / unpin, delete-for-me (hide) and delete-for-everyone all act on the
  /// shared `/chat/messages/:id/*` endpoints — the same ones the patient and
  /// doctor threads use — so the state stays consistent across all three panels.
  Future<void> _togglePin(DietMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatRepositoryProvider).setPinned(m.id, !m.pinned);
      ref.invalidate(dietThreadProvider(widget.patientId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _hide(DietMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatRepositoryProvider).hideMessage(m.id);
      ref.invalidate(dietThreadProvider(widget.patientId));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _deleteForEveryone(DietMessage m) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(chatRepositoryProvider).deleteForEveryone(m.id);
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
              accent: AppColors.accentOn(context),
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
                        itemBuilder: (context, i) {
                          final m = shown[shown.length - 1 - i];
                          return _Bubble(
                            message: m,
                            repliedTo:
                                m.replyToId == null
                                    ? null
                                    : shown
                                        .where((x) => x.id == m.replyToId)
                                        .firstOrNull,
                            onReply: () => setState(() => _replyingTo = m),
                            onTogglePin: () => _togglePin(m),
                            onHide: () => _hide(m),
                            // Only the dietician's own turns are theirs to delete
                            // for everyone; the server enforces the same rule.
                            onDeleteForEveryone:
                                m.fromDietician
                                    ? () => _deleteForEveryone(m)
                                    : null,
                          );
                        },
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
            if (_replyingTo != null)
              _DietReplyBar(
                message: _replyingTo!,
                onCancel: () => setState(() => _replyingTo = null),
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
  const _Bubble({
    required this.message,
    this.repliedTo,
    this.onReply,
    this.onTogglePin,
    this.onHide,
    this.onDeleteForEveryone,
  });

  final DietMessage message;
  final DietMessage? repliedTo;
  final VoidCallback? onReply;
  final VoidCallback? onTogglePin;
  final VoidCallback? onHide;
  final VoidCallback? onDeleteForEveryone;

  /// Long-press sheet: copy, reply, pin, delete-for-me, and (own turns only)
  /// delete-for-everyone — the same set the patient and doctor threads offer.
  Future<void> _showActions(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      builder:
          (sheet) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.content.trim().isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Copy'),
                    onTap: () async {
                      Navigator.pop(sheet);
                      await Clipboard.setData(
                        ClipboardData(text: message.content),
                      );
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Copied')),
                      );
                    },
                  ),
                if (onReply != null)
                  ListTile(
                    leading: const Icon(Icons.reply_rounded),
                    title: const Text('Reply'),
                    onTap: () {
                      Navigator.pop(sheet);
                      onReply!();
                    },
                  ),
                if (onTogglePin != null)
                  ListTile(
                    leading: Icon(
                      message.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    ),
                    title: Text(message.pinned ? 'Unpin' : 'Pin to top'),
                    onTap: () {
                      Navigator.pop(sheet);
                      onTogglePin!();
                    },
                  ),
                if (onHide != null)
                  ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('Delete for me'),
                    subtitle: const Text(
                      'Stays in the record; only removed from your view',
                      style: TextStyle(fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(sheet);
                      onHide!();
                    },
                  ),
                if (onDeleteForEveryone != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline_rounded,
                      color: AppColors.danger,
                    ),
                    title: Text(
                      'Delete for everyone',
                      style: TextStyle(color: AppColors.danger),
                    ),
                    onTap: () async {
                      Navigator.pop(sheet);
                      if (!context.mounted) return;
                      final ok = await showDialog<bool>(
                        context: context,
                        builder:
                            (dialog) => AlertDialog(
                              title: const Text('Delete for everyone'),
                              content: const Text(
                                "This message will be removed for everyone in the chat. This can't be undone.",
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.danger,
                                  ),
                                  child: const Text('Delete for everyone'),
                                ),
                              ],
                            ),
                      );
                      if (ok == true) onDeleteForEveryone!();
                    },
                  ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.fromDietician;

    // Deleted for everyone: a muted tombstone in place of the turn.
    if (message.deletedForEveryone) {
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.block_rounded,
                size: 15,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 7),
              Text(
                'This message was deleted',
                style: TextStyle(
                  fontSize: 14.5,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Matches the patient's and doctor's bubbles: a badge and a name on every
    // received turn, so a thread carrying an AI, a doctor and a dietician never
    // leaves the reader guessing which of them said something.
    final (icon, label) = switch (message.role) {
      // The patient gets a label but no picture. Their photo and name are
      // already in this screen's header, so a second copy beside every message
      // only repeats it — but with a doctor, a dietician and an assistant all
      // writing into the same thread, an unlabelled turn is the one thing a
      // reader has to work out for themselves.
      'user' => (Icons.person_rounded, 'Patient'),
      'clinician' => (
        Icons.medical_information_rounded,
        message.senderName ?? 'Doctor',
      ),
      // Named for what it is and whose it is. "AI Assistant" alone could be any
      // of a dozen things a phone runs; this one answers from the clinic's own
      // nutrition protocols, and a dietician reading the thread needs to know
      // that a machine wrote it before they act on it.
      'assistant' => (Icons.smart_toy_rounded, 'MedPin AI · nutrition assistant'),
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
            else
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The patient's turns carry the label alone — their photo is
                    // already in the app bar, and repeating it down the thread
                    // said nothing the header had not said, and said it worse.
                    if (message.role != 'user')
                    Container(
                      width: 24,
                      height: 24,
                      padding: message.role == 'assistant' ? const EdgeInsets.all(3) : null,
                      decoration: BoxDecoration(
                        color: AppColors.accentSoftOn(context),
                        shape: BoxShape.circle,
                      ),
                      // The assistant carries the app's own mark, the way it
                      // does in the patient's threads. A generic robot icon read
                      // as decoration; the emblem says which system is speaking,
                      // which is the whole point of marking these turns at all.
                      child: message.role == 'assistant'
                          ? Image.asset(
                              'assets/brand/medpin_emblem.png',
                              errorBuilder: (_, _, _) => Icon(
                                icon,
                                size: 14,
                                color: AppColors.accentOn(context),
                              ),
                            )
                          : Icon(
                              icon,
                              size: 14,
                              color: AppColors.accentOn(context),
                            ),
                    ),
                    if (message.role != 'user') const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color:
                              message.role == 'clinician'
                                  ? AppColors.accentOn(context)
                                  : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (message.pinned)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.push_pin_rounded,
                      size: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pinned',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (repliedTo != null || message.replyPreviewContent != null)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: AppColors.accentOn(context),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  repliedTo?.content ?? message.replyPreviewContent!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            GestureDetector(
              onLongPress: () => _showActions(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color:
                      mine
                          ? AppColors.bubbleMine(context)
                          : scheme.surfaceContainerLow,
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
                            color: scheme.outlineVariant.withValues(
                              alpha: 0.20,
                            ),
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
                          color:
                              mine ? Colors.white70 : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The quoted-turn strip above the composer while the dietician replies to a
/// specific message.
class _DietReplyBar extends StatelessWidget {
  const _DietReplyBar({required this.message, required this.onCancel});

  final DietMessage message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final who =
        message.fromDietician
            ? 'yourself'
            : message.role == 'user'
            ? (message.senderName ?? 'Patient')
            : (message.senderName ?? 'the clinic');
    final preview =
        message.content.trim().isNotEmpty
            ? message.content.trim()
            : (message.voiceNotes.isNotEmpty ? 'Voice message' : 'Attachment');
    return Container(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.sm, 8),
      child: Row(
        children: [
          Container(width: 3, height: 34, color: AppColors.accentOn(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to $who',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accentOn(context),
                  ),
                ),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

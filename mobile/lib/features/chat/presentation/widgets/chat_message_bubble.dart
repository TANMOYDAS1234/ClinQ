import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/markdown_text.dart';
import '../../domain/chat_message.dart';
import 'chat_attachment_thumbs.dart';
import 'citation_chips.dart';
import 'emergency_card.dart';
import 'urgent_card.dart';
import 'voice_note_player.dart';

/// Renders one turn. Assistant messages whose `urgency` is `emergency` or
/// `urgent` bypass the normal bubble entirely and render inside the
/// dedicated safety cards instead â€” this is intentional and must not be
/// "simplified" back into a plain bubble.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.onFlag,
    this.onRetry,
    this.onReply,
    this.onTogglePin,
    this.onHide,
    this.repliedTo,
    this.onQuoteTap,
    this.isClinicianView = false,
  });

  /// True in the clinician's thread. Only affects voice notes: the transcript
  /// shows there and is hidden on the patient's own recording, where it would
  /// repeat what they said a second earlier.
  final bool isClinicianView;

  final ChatMessage message;
  final VoidCallback? onFlag;

  /// Quote this message in the composer. Clinical chat runs over days, so a
  /// reply has to carry what it is answering.
  final VoidCallback? onReply;

  /// Pin or unpin. Null where pinning does not apply.
  final VoidCallback? onTogglePin;

  /// Hide from this reader's own view. Never a delete â€” see the server route.
  final VoidCallback? onHide;

  /// The message being answered, when this one is a reply.
  final ChatMessage? repliedTo;

  /// Jump to the quoted message when its preview is tapped (WhatsApp-style).
  final VoidCallback? onQuoteTap;

  /// Present only on an AI-unavailable fallback reply â€” lets the patient
  /// resend the question once the service is back.
  final VoidCallback? onRetry;

  /// A compact tappable icon in the assistant message footer (copy, flag).
  Widget _footerIcon(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// Long-press sheet: copy, reply, pin, hide.
  ///
  /// Copy is offered on every message, including the patient's own and the
  /// doctor's. A dosing instruction is exactly what someone wants to save or
  /// send to a family member, and it was previously available only on the
  /// assistant's replies.
  Future<void> _showActions(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(l10n.chatCopy),
              onTap: () async {
                Navigator.pop(sheet);
                await Clipboard.setData(ClipboardData(text: message.content));
                messenger.showSnackBar(SnackBar(content: Text(l10n.chatCopied)));
              },
            ),
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(l10n.chatReply),
                onTap: () {
                  Navigator.pop(sheet);
                  onReply!();
                },
              ),
            if (onTogglePin != null)
              ListTile(
                leading: Icon(message.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                title: Text(message.pinned ? l10n.chatUnpin : l10n.chatPin),
                onTap: () {
                  Navigator.pop(sheet);
                  onTogglePin!();
                },
              ),
            if (onHide != null)
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                // Named "hide", not "delete", because that is what it does: the
                // message stays in the medical record and only leaves this
                // reader's view.
                title: Text(l10n.chatHide),
                subtitle: Text(
                  l10n.chatHideNote,
                  style: const TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  onHide!();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// `12:45 PM`, matching the timestamps in the design.
  String _timestamp(DateTime at) {
    final local = at.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    // Safety cards represent a triage verdict about the patient's own message.
    // A clinician's reply is a person talking, so it never renders as one even
    // if the turn inherited an urgency from the conversation.
    final isClinician = message.isClinician;

    if (!message.isUser && !isClinician && message.isEmergency) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: EmergencyCard(content: message.content),
      );
    }
    if (!message.isUser && !isClinician && message.isUrgent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: UrgentCard(content: message.content),
      );
    }

    final isUser = message.isUser;

    // Which side of the conversation the reader is on.
    //
    // "Mine" is not a property of the message â€” it depends on who is looking.
    // A patient's turn belongs on the right in their own app and on the left in
    // the clinic's. Keying alignment off `isUser` alone mirrored the entire
    // thread for the doctor: the patient's words appeared as though the doctor
    // had sent them, and the doctor's own replies looked received.
    final isMine = isClinicianView ? message.isClinician : isUser;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Photos the patient attached, shown above their text.
            if (message.attachmentPaths.isNotEmpty)
              ChatAttachmentThumbs(paths: message.attachmentPaths),
            // Name the human. A patient must never have to guess whether the
            // words they are reading came from their doctor or from software.
            if (isClinician) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.medical_information_rounded, size: 15, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        message.senderName ?? l10n.chatFromClinic,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (message.pinned)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.push_pin_rounded, size: 13, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      l10n.chatPinned,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            // The quoted turn this message answers, so a reply arriving hours
            // later still says what it is about. Prefer the locally-loaded
            // original; fall back to the server-sent preview so the quote shows
            // on every device even when the original is not loaded here.
            if (repliedTo != null || message.replyPreviewContent != null)
              GestureDetector(
                onTap: onQuoteTap,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
                  ),
                  child: Text(
                    repliedTo?.content ?? message.replyPreviewContent!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            GestureDetector(
              onLongPress: () => _showActions(context),
              child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.primary
                    : isClinician
                    // Tinted, not grey: the doctor's own words carry more
                    // weight than the assistant's and should look like it.
                    ? AppColors.primary.withValues(alpha: 0.10)
                    : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isMine ? 20 : 6),
                  bottomRight: Radius.circular(isMine ? 6 : 20),
                ),
                border: isMine
                    ? null
                    : Border.all(
                        color: isClinician
                            ? AppColors.primary.withValues(alpha: 0.35)
                            : scheme.outlineVariant,
                      ),
              ),
              child: message.voiceNotes.isNotEmpty
                  // A spoken message renders as a player, not as its own
                  // transcript repeated â€” the player already shows the words.
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final note in message.voiceNotes)
                          VoiceNotePlayer(
                            note: note,
                            onDark: isUser,
                            // The sender never needs their own words read back.
                            showTranscript: isClinicianView || !isUser,
                          ),
                      ],
                    )
                  : isUser
                  // The patient's own text is never Markdown â€” render it plain.
                  ? Text(
                      message.content,
                      style: const TextStyle(fontSize: 17, height: 1.5, color: Colors.white),
                    )
                  // Assistant replies carry **bold** and `- ` bullets; render
                  // them rather than showing the raw marks.
                  //
                  // Not selectable: long-press now opens the action sheet, and
                  // text selection would swallow that gesture on assistant
                  // replies only â€” the same press doing different things
                  // depending on who spoke. Copy is in the sheet instead.
                  : MarkdownText(
                      data: message.content,
                      selectable: false,
                      style: TextStyle(
                        fontSize: 17,
                        // 1.5 gives Bengali conjuncts and Devanagari matras room
                        // to breathe; 1.4 clips their upper marks at this size.
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
            ),
            ),
            if (message.createdAt != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _timestamp(message.createdAt!),
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    // Only on the patient's own turns, and only once a person
                    // from the clinic has opened the thread. Says their message
                    // was read without implying a reply is seconds away.
                    if (isUser && message.seenByClinicAt != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.done_all_rounded, size: 15, color: AppColors.primary),
                      const SizedBox(width: 3),
                      Text(
                        l10n.chatSeenByClinic,
                        style: const TextStyle(fontSize: 12, color: AppColors.primary),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            // Citations, retry and the "AI-assisted guidance" note all describe
            // the assistant. None of them apply to something a doctor wrote,
            // and the disclaimer would actively misrepresent it.
            if (!isUser && !isClinician) ...[
              if (message.citations != null && message.citations!.isNotEmpty)
                CitationChips(citations: message.citations!),
              // A fallback reply is the scripted "service unavailable" text â€”
              // offer to resend the question rather than leaving a dead end.
              if (message.isFallback == true && onRetry != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: scheme.outlineVariant),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(l10n.chatRetry),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _footerIcon(
                    context,
                    icon: Icons.copy_rounded,
                    label: l10n.chatCopy,
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: MarkdownText.toPlainText(message.content)),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(l10n.chatCopied)));
                      }
                    },
                  ),
                  if (onFlag != null)
                    _footerIcon(
                      context,
                      icon: Icons.flag_outlined,
                      label: l10n.chatFlagMessage,
                      onTap: onFlag!,
                    ),
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      l10n.chatDisclaimer,
                      style: TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

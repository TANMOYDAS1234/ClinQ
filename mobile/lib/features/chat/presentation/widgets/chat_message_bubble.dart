import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/markdown_text.dart';
import '../../domain/chat_message.dart';
import 'citation_chips.dart';
import 'emergency_card.dart';
import 'urgent_card.dart';

/// Renders one turn. Assistant messages whose `urgency` is `emergency` or
/// `urgent` bypass the normal bubble entirely and render inside the
/// dedicated safety cards instead — this is intentional and must not be
/// "simplified" back into a plain bubble.
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({super.key, required this.message, this.onFlag, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onFlag;

  /// Present only on an AI-unavailable fallback reply — lets the patient
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

    if (!message.isUser && message.isEmergency) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: EmergencyCard(content: message.content),
      );
    }
    if (!message.isUser && message.isUrgent) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: UrgentCard(content: message.content),
      );
    }

    final isUser = message.isUser;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 6),
                  bottomRight: Radius.circular(isUser ? 6 : 20),
                ),
                border: isUser ? null : Border.all(color: scheme.outlineVariant),
              ),
              child: isUser
                  // The patient's own text is never Markdown — render it plain.
                  ? Text(
                      message.content,
                      style: const TextStyle(fontSize: 17, height: 1.5, color: Colors.white),
                    )
                  // Assistant replies carry **bold** and `- ` bullets; render
                  // them rather than showing the raw marks. Selectable so a
                  // patient can long-press to pick out and copy a word.
                  : MarkdownText(
                      data: message.content,
                      selectable: true,
                      style: TextStyle(
                        fontSize: 17,
                        // 1.5 gives Bengali conjuncts and Devanagari matras room
                        // to breathe; 1.4 clips their upper marks at this size.
                        height: 1.5,
                        color: scheme.onSurface,
                      ),
                    ),
            ),
            if (message.createdAt != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  _timestamp(message.createdAt!),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            if (!isUser) ...[
              if (message.citations != null && message.citations!.isNotEmpty)
                CitationChips(citations: message.citations!),
              // A fallback reply is the scripted "service unavailable" text —
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

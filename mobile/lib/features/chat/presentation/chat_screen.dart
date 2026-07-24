import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/widgets/loading_view.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/chat_message.dart';
import 'chat_controller.dart';
import 'chat_sessions_provider.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/dotted_background.dart';
import 'widgets/generating_bubble.dart';
import 'widgets/session_drawer.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scrollController = ScrollController();

  /// Whether the list is scrolled far enough from the bottom to warrant the
  /// jump-to-latest button. Reversed lists put "latest" at offset 0, but this
  /// list is bottom-anchored, so "away from latest" means below maxScrollExtent.
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final away = pos.maxScrollExtent - pos.pixels > 240;
    if (away != _showJumpToLatest) setState(() => _showJumpToLatest = away);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  /// See [resolveReplyLanguage] — the app's displayed locale wins over the
  /// language stored on the account.
  String get _replyLanguage => resolveReplyLanguage(
    appLocale: ref.read(localeControllerProvider)?.languageCode,
    accountLanguage: ref.read(authControllerProvider).user?.language,
  );

  Future<void> _send(String text, [List<String> attachments = const []]) async {
    await ref
        .read(chatControllerProvider.notifier)
        .send(text: text, language: _replyLanguage, attachments: attachments);
    ref.invalidate(chatSessionsProvider);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chatState = ref.watch(chatControllerProvider);
    // Watched, not read, so switching language in Profile immediately
    // re-points the speech recogniser at the new locale.
    ref.watch(localeControllerProvider);
    final language = _replyLanguage;

    ref.listen(chatControllerProvider, (previous, next) {
      if (previous?.messages.length != next.messages.length) _scrollToBottom();
    });

    final entries = _withDateSeparators(chatState.messages);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.chatTitle,
          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: l10n.chatNewChat,
            icon: const Icon(Icons.add_rounded, size: 28),
            onPressed: () => ref.read(chatControllerProvider.notifier).startNewChat(),
          ),
        ],
      ),
      drawer: const SessionDrawer(),
      body: DottedBackground(
        child: Column(
          children: [
            if (chatState.error != null)
              Container(
                width: double.infinity,
                color: AppColors.dangerBg,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  _errorMessage(context, chatState.error!.code),
                  style: const TextStyle(color: AppColors.danger),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  chatState.isLoadingHistory
                  ? const LoadingView()
                  : chatState.messages.isEmpty
                  ? ChatEmptyState(onSuggestionTap: _send)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: entries.length + (chatState.isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == entries.length) return const GeneratingBubble();

                        final entry = entries[index];
                        if (entry.separatorLabel != null) {
                          return _DateSeparator(label: entry.separatorLabel!);
                        }

                        final message = entry.message!;
                        // Each bubble is its own repaint layer, so a keyboard
                        // resize or a new message repaints one row, not the
                        // whole transcript.
                        return RepaintBoundary(
                          child: ChatMessageBubble(
                            message: message,
                            onRetry: message.isUser
                                ? null
                                : () => ref
                                    .read(chatControllerProvider.notifier)
                                    .retryLast(language: language),
                            onFlag: message.isUser
                                ? null
                                : () async {
                                    final ok = await ref
                                        .read(chatControllerProvider.notifier)
                                        .flagMessage(message.id);
                                    if (ok && context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(SnackBar(content: Text(l10n.chatFlagSent)));
                                    }
                                  },
                          ),
                        );
                      },
                    ),
                  if (_showJumpToLatest)
                    Positioned(
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: _JumpToLatestButton(
                        label: l10n.chatScrollToLatest,
                        onTap: _scrollToBottom,
                      ),
                    ),
                ],
              ),
            ),
            ChatComposer(
              onSend: _send,
              isSending: chatState.isSending,
              languageCode: language,
            ),
          ],
        ),
      ),
    );
  }

  /// Interleaves "Today" / "Yesterday" / date markers between messages.
  ///
  /// Messages loaded from history carry `createdAt`; a session spanning more
  /// than one day is otherwise an undifferentiated wall of bubbles.
  List<_Entry> _withDateSeparators(List<ChatMessage> messages) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final entries = <_Entry>[];
    DateTime? lastDay;

    for (final m in messages) {
      final at = m.createdAt?.toLocal();
      if (at != null) {
        final day = DateTime(at.year, at.month, at.day);
        if (lastDay == null || day != lastDay) {
          entries.add(_Entry.separator(_labelFor(day, now, l10n)));
          lastDay = day;
        }
      }
      entries.add(_Entry.message(m));
    }
    return entries;
  }

  String _labelFor(DateTime day, DateTime now, AppLocalizations l10n) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return l10n.chatDateToday;
    if (diff == 1) return l10n.chatDateYesterday;
    return '${day.day.toString().padLeft(2, '0')}/'
        '${day.month.toString().padLeft(2, '0')}/${day.year}';
  }

  String _errorMessage(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context);
    if (code == 'AI_UNAVAILABLE') return l10n.errorAiUnavailable;
    if (code == 'NETWORK_ERROR' || code == 'TIMEOUT') return l10n.commonNoInternet;
    return l10n.commonSomethingWentWrong;
  }
}

/// Floating pill that returns the patient to the newest message after they
/// have scrolled up to re-read the conversation.
class _JumpToLatestButton extends StatelessWidget {
  const _JumpToLatestButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.primaryDark : AppColors.primary,
      borderRadius: BorderRadius.circular(24),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list row: either a message or a date separator.
class _Entry {
  const _Entry.message(this.message) : separatorLabel = null;
  const _Entry.separator(this.separatorLabel) : message = null;

  final ChatMessage? message;
  final String? separatorLabel;
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

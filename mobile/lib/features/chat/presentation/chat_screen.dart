import 'dart:async';

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
import 'widgets/chat_composer.dart';
import 'widgets/chat_empty_state.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/dotted_background.dart';
import 'widgets/generating_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _scrollController = ScrollController();

  /// Polls for messages the patient did not send — a reply from the clinic.
  ///
  /// There is no socket or push channel, so the conversation is kept live by
  /// re-reading it. Three seconds is short enough that a doctor's reply lands
  /// while the patient is still looking at the screen, and the request is
  /// cheap: one indexed query, and state is only touched when something new
  /// actually arrived.
  static const _pollInterval = Duration(seconds: 3);
  Timer? _poll;

  /// Whether the list is scrolled far enough from the bottom to warrant the
  /// jump-to-latest button. Reversed lists put "latest" at offset 0, but this
  /// list is bottom-anchored, so "away from latest" means below maxScrollExtent.
  bool _showJumpToLatest = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    // Resume the patient's ongoing conversation rather than opening blank.
    // Deferred past the first frame because it mutates a provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(chatControllerProvider.notifier).resumeLatest();
    });
    _poll = Timer.periodic(_pollInterval, (_) {
      if (mounted) ref.read(chatControllerProvider.notifier).pollForUpdates();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the background is when the conversation is most likely to
    // have moved on, so check at once instead of waiting out the timer.
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(chatControllerProvider.notifier).pollForUpdates();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final away = pos.maxScrollExtent - pos.pixels > 240;
    if (away != _showJumpToLatest) setState(() => _showJumpToLatest = away);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
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
      final lengthChanged = previous?.messages.length != next.messages.length;
      // Also follow a streaming reply, whose length is fixed but whose last
      // message's content grows token by token.
      final contentGrew = previous != null &&
          previous.messages.isNotEmpty &&
          next.messages.isNotEmpty &&
          previous.messages.last.content.length != next.messages.last.content.length;
      if (lengthChanged || contentGrew) _scrollToBottom();
    });

    // The assistant's bubble is created when the `meta` event lands, which is
    // before the first token of its reply. Drawing it in that window rendered
    // an empty bubble for a moment, so hold it back until it has text.
    final messages = chatState.messages;
    final awaitingFirstToken =
        messages.isNotEmpty && !messages.last.isUser && messages.last.content.isEmpty;

    final entries = _withDateSeparators(
      awaitingFirstToken ? messages.sublist(0, messages.length - 1) : messages,
    );

    // The "analysing" bubble covers the whole wait — from send until there is
    // actual text — so the two never swap to a blank gap in between. Once the
    // reply starts streaming it would be a duplicate, so it goes.
    final showGenerating =
        chatState.isSending && (messages.isEmpty || messages.last.isUser || awaitingFirstToken);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.chatTitle,
          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
        // No "new chat" action: the patient has one continuous conversation
        // with the assistant, which the doctor reviews as a single thread.
      ),
      // The Scaffold does not resize for the keyboard; instead the content is
      // padded by the keyboard inset below. This keeps the dotted background a
      // fixed, full-screen layer that never repaints as the keyboard animates —
      // which was a real source of the input/attach lag.
      resizeToAvoidBottomInset: false,
      body: DottedBackground(
        child: _KeyboardInset(
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
                      itemCount: entries.length + (showGenerating ? 1 : 0),
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

/// Lifts the conversation above the keyboard, without rebuilding it.
///
/// The Scaffold has `resizeToAvoidBottomInset: false` so the dotted background
/// stays a fixed layer, and the keyboard inset is applied here instead. Reading
/// the inset in [_ChatScreenState.build] subscribed the whole screen to
/// MediaQuery, so every frame of the keyboard's open animation rebuilt the
/// transcript, the date separators and the composer — which is what made
/// tapping the field and the attach button feel slow.
///
/// Reading it here confines that per-frame rebuild to this one widget: [child]
/// arrives already built, so Flutter sees an identical widget instance and
/// skips the subtree entirely. Only the padding value changes.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // viewInsetsOf, not MediaQuery.of: subscribes to the insets alone rather
    // than to every MediaQuery change (text scale, orientation, padding…).
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
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

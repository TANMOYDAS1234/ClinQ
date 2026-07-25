import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/widgets/auto_refresh.dart';
import '../data/messaging_repository.dart';
import '../domain/direct_message.dart';

/// The human doctor↔patient chat, in the same bubble/composer style as the AI
/// assistant. One screen serves both sides:
///   * [patientId] null  → the patient messaging the clinic (their own thread)
///   * [patientId] set   → a clinician messaging that patient
class ClinicChatScreen extends ConsumerStatefulWidget {
  const ClinicChatScreen({super.key, this.patientId, this.title});

  final String? patientId;
  final String? title;

  bool get _clinicianView => patientId != null;

  @override
  ConsumerState<ClinicChatScreen> createState() => _ClinicChatScreenState();
}

class _ClinicChatScreenState extends ConsumerState<ClinicChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  static const _poll = Duration(seconds: 5);

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  ProviderListenable<AsyncValue<List<DirectMessage>>> get _provider =>
      widget._clinicianView ? patientThreadProvider(widget.patientId!) : myThreadProvider;

  void _invalidate() {
    if (widget._clinicianView) {
      ref.invalidate(patientThreadProvider(widget.patientId!));
    } else {
      ref.invalidate(myThreadProvider);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = ref.read(messagingRepositoryProvider);
      if (widget._clinicianView) {
        await repo.sendToPatient(widget.patientId!, text);
      } else {
        await repo.sendAsPatient(text);
      }
      _controller.clear();
      _invalidate();
      _scrollToBottom();
    } on ApiException {
      messenger.showSnackBar(const SnackBar(content: Text('Could not send. Please try again.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(_provider);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? l10n.msgClinicTitle)),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: AutoRefresh(
              interval: _poll,
              onTick: (_) => _invalidate(),
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.commonSomethingWentWrong),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton(onPressed: _invalidate, child: Text(l10n.commonRetry)),
                    ],
                  ),
                ),
                data: (messages) {
                  if (messages.isEmpty) {
                    return _EmptyState(clinicianView: widget._clinicianView);
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      // "Mine" flips depending on which side is viewing.
                      final mine = widget._clinicianView ? !m.fromPatient : m.fromPatient;
                      return _Bubble(message: m, mine: mine);
                    },
                  );
                },
              ),
            ),
          ),
          _Composer(controller: _controller, sending: _sending, onSend: _send),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final DirectMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mineColor = isDark ? AppColors.primaryDark : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine && message.senderName != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text(
                message.senderName!,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
              ),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? mineColor : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Text(
              message.content,
              style: TextStyle(fontSize: 15.5, height: 1.4, color: mine ? Colors.white : scheme.onSurface),
            ),
          ),
          if (message.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 6, right: 6),
              child: Text(
                DateFormat('h:mm a').format(message.createdAt!),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
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
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    return Container(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, maxHeight: 140),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Center(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: l10n.msgComposerHint,
                    border: InputBorder.none,
                    isCollapsed: true,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: sending ? null : onSend,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.clinicianView});
  final bool clinicianView;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.msgEmpty, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              clinicianView ? l10n.msgEmptyClinician : l10n.msgEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

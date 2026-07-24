import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../l10n/gen/app_localizations.dart';
import '../../../../shared/widgets/empty_view.dart';
import '../../../../shared/widgets/error_view.dart';
import '../../../../shared/widgets/loading_view.dart';
import '../../domain/chat_session.dart';
import '../chat_controller.dart';
import '../chat_sessions_provider.dart';

class SessionDrawer extends ConsumerWidget {
  const SessionDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessionsAsync = ref.watch(chatSessionsProvider);
    final currentSessionId = ref.watch(chatControllerProvider).sessionId;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(l10n.chatSessions, style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref.read(chatControllerProvider.notifier).startNewChat();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.chatNewChat),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            Expanded(
              child: sessionsAsync.when(
                loading: () => const LoadingView(),
                error: (error, _) => ErrorView(
                  error: error,
                  onRetry: () => ref.invalidate(chatSessionsProvider),
                ),
                data: (paged) {
                  if (paged.items.isEmpty) {
                    return EmptyView(
                      icon: Icons.forum_outlined,
                      title: l10n.chatSessionsEmpty,
                    );
                  }
                  return ListView.builder(
                    itemCount: paged.items.length,
                    itemBuilder: (context, index) {
                      final session = paged.items[index];
                      final isSelected = session.id == currentSessionId;
                      return _SessionTile(
                        session: session,
                        isSelected: isSelected,
                        onTap: () {
                          ref.read(chatControllerProvider.notifier).openSession(session.id);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.isSelected, required this.onTap});

  final ChatSession session;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      selected: isSelected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.4),
      leading: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
      title: Text(
        session.title?.isNotEmpty == true
            ? session.title!
            : (session.lastMessagePreview ?? '—'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: session.lastMessageAt == null
          ? null
          : Text(DateFormat('d MMM, h:mm a').format(session.lastMessageAt!.toLocal())),
      onTap: onTap,
    );
  }
}

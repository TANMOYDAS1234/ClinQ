import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/auto_refresh.dart';
import '../data/messaging_repository.dart';
import '../domain/direct_message.dart';

/// The clinician's message inbox: one row per patient conversation, newest
/// first, with an unread badge. Tapping opens the thread.
class ClinicianMessagesScreen extends ConsumerWidget {
  const ClinicianMessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(messageThreadsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: AutoRefresh(
        interval: const Duration(seconds: 8),
        onTick: (r) => r.invalidate(messageThreadsProvider),
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(messageThreadsProvider),
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load messages'),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(onPressed: () => ref.invalidate(messageThreadsProvider), child: const Text('Retry')),
                ],
              ),
            ),
            data: (threads) {
              if (threads.isEmpty) {
                return ListView(
                  children: [
                    SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                    Icon(Icons.forum_outlined, size: 56, color: scheme.outlineVariant),
                    const SizedBox(height: AppSpacing.md),
                    const Center(child: Text('No conversations yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                    const SizedBox(height: AppSpacing.xs),
                    Center(child: Text('Message a patient from their profile', style: TextStyle(color: scheme.onSurfaceVariant))),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: threads.length,
                separatorBuilder: (_, _) => Divider(height: 1, indent: 76, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                itemBuilder: (context, i) => _ThreadRow(thread: threads[i]),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({required this.thread});

  final MessageThread thread;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = thread;
    final initial = (t.patientName?.isNotEmpty ?? false) ? t.patientName![0].toUpperCase() : '?';
    final preview = t.lastSenderRole == 'patient' ? (t.lastMessage ?? '') : 'You: ${t.lastMessage ?? ''}';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withValues(alpha: 0.14),
        child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary, fontSize: 18)),
      ),
      title: Text(t.patientName ?? 'Patient', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: t.unread > 0 ? scheme.onSurface : scheme.onSurfaceVariant,
          fontWeight: t.unread > 0 ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (t.lastAt != null)
            Text(DateFormat('d MMM').format(t.lastAt!), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          if (t.unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text('${t.unread}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      onTap: () => context.push('/clinician/messages/${t.patientId}', extra: t.patientName),
    );
  }
}

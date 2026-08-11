import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../domain/chat_review.dart';
import 'clinician_providers.dart';

/// The doctor's Nutrition tab: every dietician↔patient conversation as an inbox,
/// like the Patients tab. Tapping a row opens the thread in the same WhatsApp
/// chat UI — the doctor reads the dietician's and the patient's messages (and
/// the assistant's), and can step in to guide when something needs correcting.
class NutritionInboxScreen extends ConsumerWidget {
  const NutritionInboxScreen({super.key});

  static const ChatReviewQuery _query = (flagged: false, urgency: null, kind: 'nutrition');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(chatReviewProvider(_query));

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Nutrition'),
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(chatReviewProvider(_query)),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(child: Text('Could not load conversations', style: TextStyle(color: scheme.onSurfaceVariant))),
            ],
          ),
          data: (paged) {
            final items = paged.items;
            if (items.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.restaurant_menu_rounded, size: 44, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('No nutrition conversations yet',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text('Dietician–patient chats appear here',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 76,
                color: scheme.outlineVariant.withValues(alpha: 0.4),
              ),
              itemBuilder: (_, i) => _NutritionRow(session: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _NutritionRow extends StatelessWidget {
  const _NutritionRow({required this.session});

  final ChatReviewSession session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = session.unreadCount > 0;
    final name = session.patientName ?? 'Patient';

    return InkWell(
      onTap: () => context.push('/clinician/chat-review/${session.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(name: name, avatarUrl: null, accent: AppColors.accentOn(context), size: 48),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
                        ),
                      ),
                      if (session.lastMessageAt != null)
                        Text(
                          _stampFull(session.lastMessageAt!),
                          style: TextStyle(
                            fontSize: 13,
                            color: unread ? AppColors.accentOn(context) : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.title.isEmpty ? 'Nutrition conversation' : session.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            height: 1.35,
                            color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentOn(context),
                            borderRadius: const BorderRadius.all(Radius.circular(11)),
                          ),
                          child: Text(
                            session.unreadCount > 99 ? '99+' : '${session.unreadCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `10:42 AM` today, `Yesterday`, a weekday within the week, else `12 Oct`.
  String _stampFull(DateTime at) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(at.year, at.month, at.day)).inDays;
    if (diff == 0) {
      final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
      return '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${at.day} ${months[at.month - 1]}';
  }
}

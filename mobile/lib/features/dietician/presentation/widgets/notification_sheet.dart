import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/user_avatar.dart';
import '../../data/dietician_repository.dart';
import '../../domain/diet_models.dart';
import '../dietician_providers.dart';

/// What is waiting for the dietician, as a sheet from the bottom of the screen.
///
/// A sheet rather than a screen because this is a glance, not a destination:
/// the dietician wants to know whether anything needs them before deciding to
/// go anywhere, and a full screen with a back arrow makes that a trip.
///
/// Opening it marks the unread messages as seen. The badge should clear because
/// somebody looked, never because something was delivered.
Future<void> showDieticianNotifications(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _NotificationSheet(),
  );
}

class _NotificationSheet extends ConsumerStatefulWidget {
  const _NotificationSheet();

  @override
  ConsumerState<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends ConsumerState<_NotificationSheet> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the list the dietician is reading still shows
    // which entries were unread when they opened it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
  }

  Future<void> _markSeen() async {
    try {
      await ref.read(dieticianRepositoryProvider).markNotificationsSeen();
      ref.invalidate(dietDashboardProvider);
    } catch (_) {
      // A badge that fails to clear is a nuisance; an error toast over a sheet
      // the dietician opened to read something else is worse.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(dietNotificationsProvider);
    final view = async.valueOrNull;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      builder: (context, controller) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                if ((view?.unread ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accentOn(context),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${view!.unread}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: () => ref.invalidate(dietNotificationsProvider),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
          Expanded(
            child: switch ((view, async.isLoading)) {
              (null, true) => const Center(child: CircularProgressIndicator()),
              (null, _) => _Empty(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load notifications',
                body: 'Check your connection and pull to try again.',
              ),
              (final v, _) when v!.items.isEmpty => const _Empty(
                icon: Icons.done_all_rounded,
                title: 'Nothing waiting',
                body: 'No unread messages, no lapsed reviews, and every patient has a plan.',
              ),
              (final v, _) => ListView.separated(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                itemCount: v!.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 4),
                itemBuilder: (context, i) => _NotificationRow(item: v.items[i]),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item});

  final DietNotification item;

  /// "4m", "3h", "2d" — enough to say how stale, in the space of a chip.
  static String _ago(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return DateFormat('d MMM').format(at);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = AppColors.accentOn(context);

    // The mark says what kind of work this is, so the list can be triaged
    // without reading every line.
    final (IconData icon, Color tint) = switch (item.kind) {
      'review' => (Icons.schedule_rounded, AppColors.warningOn(context)),
      'plan' => (Icons.assignment_outlined, accent),
      _ => (Icons.chat_bubble_rounded, accent),
    };

    // An unread message goes to the conversation; the other two are about the
    // record, so they open it.
    void open() {
      Navigator.of(context).pop();
      if (item.kind == 'message') {
        context.push('/dietician/patients/${item.patientId}/chat', extra: item.patientName);
      } else if (item.kind == 'plan') {
        context.push('/dietician/patients/${item.patientId}/diet', extra: item.patientName);
      } else {
        context.push('/dietician/patients/${item.patientId}', extra: item.patientName);
      }
    }

    return Material(
      color: item.unread ? accent.withValues(alpha: 0.06) : scheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: open,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.unread
                  ? accent.withValues(alpha: 0.25)
                  : scheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    name: item.patientName,
                    avatarUrl: item.avatarUrl,
                    accent: accent,
                    size: 42,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 19,
                      height: 19,
                      decoration: BoxDecoration(
                        color: tint,
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.surface, width: 2),
                      ),
                      child: Icon(icon, size: 10, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.patientName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: item.unread ? FontWeight.w800 : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _ago(item.at),
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 0),
                    Text(
                      item.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.35,
                        color: item.unread ? scheme.onSurface : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: scheme.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

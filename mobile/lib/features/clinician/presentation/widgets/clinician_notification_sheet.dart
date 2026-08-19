import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/widgets/notification_list_sheet.dart';
import '../../data/clinician_repository.dart';
import '../clinician_providers.dart';

/// The doctor's bell, opened.
///
/// Alerts, unread patient messages from both threads, and flagged
/// conversations — the things the overview endpoint was already counting while
/// the bell showed only the first of them.
Future<void> showClinicianNotifications(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ClinicianNotificationSheet(),
  );
}

class _ClinicianNotificationSheet extends ConsumerStatefulWidget {
  const _ClinicianNotificationSheet();

  @override
  ConsumerState<_ClinicianNotificationSheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_ClinicianNotificationSheet> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the list the doctor is reading still shows
    // which rows were unread when they opened it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
  }

  Future<void> _markSeen() async {
    try {
      await ref.read(clinicianRepositoryProvider).markNotificationsSeen();
      ref.invalidate(overviewProvider);
    } catch (_) {
      // A badge that fails to clear is a nuisance. An error toast over a sheet
      // the doctor opened to read something else is worse.
    }
  }

  /// Where each row leads. An alert opens the alerts screen, which is where it
  /// can be acted on; a message opens the patient it came from.
  void _open(PanelNotification item) {
    Navigator.of(context).pop();
    switch (item.kind) {
      case 'urgent':
      case 'alert':
        context.push('/clinician/alerts');
      case 'review':
        context.push('/clinician/chat-review');
      default:
        // The conversation, not the record: an unread message is answered in
        // the thread, and landing on the profile makes the doctor find it.
        if (item.patientId.isNotEmpty) {
          context.push('/clinician/patients/${item.patientId}/thread');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(clinicianNotificationsProvider);
    final view = async.valueOrNull;

    return NotificationListSheet(
      items: view?.items ?? const [],
      unread: view?.unread ?? 0,
      loading: async.isLoading,
      failed: view == null && async.hasError,
      onRefresh: () => ref.invalidate(clinicianNotificationsProvider),
      onOpen: _open,
      emptyBody: 'No open alerts, no unread messages, nothing flagged for review.',
    );
  }
}

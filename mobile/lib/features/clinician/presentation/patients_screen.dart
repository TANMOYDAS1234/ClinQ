import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';

/// The clinician's inbox.
///
/// Deliberately a conversation list rather than a clinical directory: reaching a
/// waiting patient is the daily job, and the question the doctor opens the app
/// to answer is "who is waiting on me", not "who has the worst HbA1c". Risk and
/// alerts still appear, but as marks on a row, not as the organising principle.
///
/// Rows sort unread-first, then by most recent message, so the list orders
/// itself around that question without the doctor having to filter.
class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  String _search = '';
  Timer? _debounce;
  Timer? _poll;

  /// Only unread conversations, when the doctor wants the queue and nothing else.
  bool _unreadOnly = false;

  /// The inbox is only useful if it is current. There is no socket, so it
  /// re-reads on a timer while on screen and immediately on resume.
  static const _pollInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(_pollInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the background is the likeliest moment for a new message
    // to have arrived, so check at once rather than waiting out the timer.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (mounted) ref.invalidate(patientsProvider(_query));
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _search = v.trim());
    });
  }

  PatientsQuery get _query =>
      (riskBand: null, search: _search.isEmpty ? null : _search, sort: 'name');

  /// Unread first, then newest message. A patient who has never written sinks
  /// to the bottom — there is nothing waiting there.
  List<PatientListItem> _ordered(List<PatientListItem> items) {
    final list = [...items];
    list.sort((a, b) {
      if ((a.unreadCount > 0) != (b.unreadCount > 0)) return a.unreadCount > 0 ? -1 : 1;
      final at = a.lastMessage?.at;
      final bt = b.lastMessage?.at;
      if (at == null && bt == null) return a.name.compareTo(b.name);
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(patientsProvider(_query));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _InboxHeader(),
            _SearchField(controller: _searchController, onChanged: _onSearchChanged),
            _SectionBar(
              unreadOnly: _unreadOnly,
              onToggleFilter: () => setState(() => _unreadOnly = !_unreadOnly),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, _) => ListView(
                    children: [
                      SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      const Center(child: Text('Could not load messages')),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                      ),
                    ],
                  ),
                  data: (paged) {
                    var items = _ordered(paged.items);
                    if (_unreadOnly) items = items.where((p) => p.unreadCount > 0).toList();

                    if (items.isEmpty) {
                      return ListView(
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                          Icon(
                            _unreadOnly ? Icons.mark_email_read_outlined : Icons.forum_outlined,
                            size: 52,
                            color: scheme.outlineVariant,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Center(
                            child: Text(
                              _unreadOnly ? 'Nothing unread' : 'No conversations yet',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      );
                    }

                    // One grouped card with hairline dividers, rather than a
                    // separate floating card per patient — a long inbox of
                    // detached cards reads as clutter.
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.lg,
                      ),
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < items.length; i++) ...[
                                if (i > 0)
                                  Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)),
                                _ConversationRow(
                                  patient: items[i],
                                  onTap: () => context.push(
                                    '/clinician/patients/${items[i].id}/thread',
                                    extra: items[i].name,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Brand row. Uses the app's own mark, not a generic medical cross.
class _InboxHeader extends StatelessWidget {
  const _InboxHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          // The app's own emblem, not a generic medical cross.
          Image.asset(
            'assets/brand/logo_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.forum_rounded, size: 26, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text(
            'ClinQ',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 15.5),
        decoration: InputDecoration(
          hintText: 'Search patients or messages…',
          prefixIcon: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
          filled: true,
          fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.unreadOnly, required this.onToggleFilter});

  final bool unreadOnly;
  final VoidCallback onToggleFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.sm, AppSpacing.md),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Patient Messages',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
          ),
          TextButton(
            onPressed: onToggleFilter,
            child: Text(
              unreadOnly ? 'Show all' : 'Unread',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// One conversation. Reads top-to-bottom as: who, when, what was last said,
/// and whether it needs the doctor.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.patient, required this.onTap});

  final PatientListItem patient;
  final VoidCallback onTap;

  /// `10:42 AM` today, `Yesterday`, a weekday within the week, else `12 Oct`.
  String _stamp(DateTime at) {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;

    if (diff == 0) {
      final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
      return '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) {
      return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][at.weekday - 1];
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${at.day} ${months[at.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final msg = patient.lastMessage;
    final unread = patient.unreadCount > 0;
    final emergency = msg?.urgency == 'emergency' || msg?.urgency == 'urgent';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              name: patient.name,
              avatarUrl: patient.avatarUrl,
              accent: emergency ? AppColors.danger : AppColors.primary,
              size: 48,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          patient.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.5,
                            // Unread rows carry the weight, so the queue is
                            // visible without reading a single word.
                            fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (msg != null)
                        Text(
                          _stamp(msg.at),
                          style: TextStyle(
                            fontSize: 13,
                            color: unread ? AppColors.primary : scheme.onSurfaceVariant,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    msg == null
                        ? 'No messages yet'
                        // Say who spoke, so "answered" and "waiting" are
                        // distinguishable at a glance.
                        : msg.fromPatient
                        ? msg.preview
                        : 'You: ${msg.preview}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.35,
                      color: msg == null
                          ? scheme.outline
                          : unread
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                      fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (unread || emergency || patient.openAlertCount > 0) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (emergency)
                          const _Chip(
                            label: 'Needs attention',
                            fg: AppColors.danger,
                            bg: AppColors.dangerBg,
                            icon: Icons.priority_high_rounded,
                          ),
                        if (unread)
                          _Chip(
                            label: patient.unreadCount == 1
                                ? 'New message'
                                : '${patient.unreadCount} new messages',
                            fg: AppColors.primary,
                            bg: AppColors.accentSoft,
                            icon: Icons.mark_chat_unread_rounded,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.fg, required this.bg, required this.icon});

  final String label;
  final Color fg;
  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
          ),
        ],
      ),
    );
  }
}

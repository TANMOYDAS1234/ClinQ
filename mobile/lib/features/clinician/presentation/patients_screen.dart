import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/markdown_text.dart';
import '../../../shared/widgets/user_avatar.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/clinician_models.dart';
import 'clinician_providers.dart';
import 'widgets/sparkline.dart';

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
  ///
  /// Matched to the conversation screens rather than the twenty seconds a list
  /// view would normally justify: this is the screen a doctor sits on while
  /// waiting for a patient to reply, and a message that takes twenty seconds to
  /// appear reads as the app being broken.
  static const _pollInterval = Duration(seconds: 3);

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
      // Desk intake: register a walk-in patient without leaving the directory.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/clinician/patients/new'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add patient'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const _InboxHeader(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  children: [
                    _SectionBar(
                      unreadOnly: _unreadOnly,
                      onSelect: (v) => setState(() => _unreadOnly = v),
                    ),
                    _SearchField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    async.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            const Text('Could not load messages'),
                            const SizedBox(height: AppSpacing.sm),
                            OutlinedButton(onPressed: _refresh, child: const Text('Retry')),
                          ],
                        ),
                      ),
                      data: (paged) {
                        var items = _ordered(paged.items);
                        if (_unreadOnly) items = items.where((p) => p.unreadCount > 0).toList();

                        if (items.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: [
                                Icon(
                                  _unreadOnly ? Icons.mark_email_read_outlined : Icons.forum_outlined,
                                  size: 52,
                                  color: scheme.outlineVariant,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  _unreadOnly ? 'Nothing unread' : 'No conversations yet',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          );
                        }

                        // A separate card per conversation (per the redesign),
                        // with a red rail on anything flagged urgent/emergency.
                        return Column(
                          children: [
                            for (final it in items)
                              Container(
                                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerLowest,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.22)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 14,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      if (it.lastMessage?.urgency == 'emergency' ||
                                          it.lastMessage?.urgency == 'urgent')
                                        Container(width: 4, color: AppColors.danger),
                                      Expanded(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: _ConversationRow(
                                            patient: it,
                                            onTap: () => context.push(
                                              '/clinician/patients/${it.id}/thread',
                                              extra: it.name,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
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
class _InboxHeader extends ConsumerWidget {
  const _InboxHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // The app's own emblem, not a generic medical cross.
          Image.asset(
            'assets/brand/medpin_emblem.png',
            height: 30,
            errorBuilder: (_, _, _) =>
                Icon(Icons.forum_rounded, size: 26, color: AppColors.accentOn(context)),
          ),
          const SizedBox(width: 10),
          Text(
            'MedPin Panel',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentOn(context)),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => context.push('/clinician/alerts'),
            icon: Icon(Icons.notifications_none_rounded, size: 24, color: scheme.onSurfaceVariant),
            tooltip: 'Alerts',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => context.push('/clinician/more'),
            child: UserAvatar(
              name: user?.name ?? '',
              avatarUrl: user?.avatarUrl,
              accent: AppColors.accentOn(context),
              size: 38,
            ),
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
      padding: EdgeInsets.zero,
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
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide(color: AppColors.accentOn(context), width: 1.6),
          ),
        ),
      ),
    );
  }
}

class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.unreadOnly, required this.onSelect});

  final bool unreadOnly;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Care Inbox',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Seg(label: 'Unread', selected: unreadOnly, onTap: () => onSelect(true)),
                _Seg(label: 'Show all', selected: !unreadOnly, onTap: () => onSelect(false)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// One segment of the pill toggle — the selected one lifts onto a white pill.
class _Seg extends StatelessWidget {
  const _Seg({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerLowest : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: selected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (msg == null)
                                const TextSpan(text: 'No messages yet')
                              else ...[
                                // Say who spoke, so "answered" and "waiting" are
                                // distinguishable at a glance.
                                if (!msg.fromPatient) const TextSpan(text: 'You: '),
                                // A subtle monochrome icon for a media turn —
                                // premium, not a cheap emoji.
                                if (msg.mediaType != null)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(
                                        _mediaIcon(msg.mediaType!),
                                        size: 15,
                                        color: unread ? scheme.onSurface : scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                TextSpan(text: MarkdownText.toPreview(msg.preview)),
                              ],
                            ],
                          ),
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
                      ),
                      // WhatsApp-style unread count: a green disc with just the
                      // number, on the right of the preview line. Expands to a
                      // pill for two digits, "99+" beyond.
                      if (unread) ...[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.accentOn(context),
                            borderRadius: BorderRadius.all(Radius.circular(11)),
                          ),
                          child: Text(
                            patient.unreadCount > 99 ? '99+' : '${patient.unreadCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (emergency) ...[
                    const SizedBox(height: 8),
                    _Chip(
                      label: 'Needs attention',
                      fg: AppColors.dangerOn(context),
                      bg: AppColors.dangerBgOn(context),
                      icon: Icons.priority_high_rounded,
                    ),
                  ],
                  _MonitorStrip(patient: patient),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The continuous-monitoring mark on an inbox row: a glucose sparkline, when the
/// patient last checked in, which way control is heading, and an amber flag when
/// they are overdue. A glance-able mark, not a reorganisation of the list.
class _MonitorStrip extends StatelessWidget {
  const _MonitorStrip({required this.patient});

  final PatientListItem patient;

  /// `today`, `1d ago`, `5d ago`, `3w ago`.
  String _ago(DateTime at) {
    final days = DateTime.now().difference(at).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return '1d ago';
    if (days < 21) return '${days}d ago';
    return '${(days / 7).round()}w ago';
  }

  static Color _hba1cColor(num v, BuildContext c) =>
      v >= 9 ? AppColors.dangerOn(c) : (v >= 7 ? AppColors.warningOn(c) : AppColors.successOn(c));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hba1c = patient.hba1c;
    final overdue = patient.checkInOverdue;
    final hasGlucoseSpark = patient.spark.length >= 2;
    final lastGlucose = patient.lastReadingAt;

    // Nothing to show yet — keep the row clean.
    if (hba1c == null && !hasGlucoseSpark && lastGlucose == null && !overdue) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    if (hba1c != null) {
      // The doctor's anchor: HbA1c, coloured by control, with a mini-trend.
      final color = _hba1cColor(hba1c, context);
      // The trend line is GLUCOSE, not HbA1c. HbA1c is measured every few months,
      // so it can't form a line; and its 5-9% values fed into a glucose-scaled
      // chart drew the 70-180 target band as a grey block above a crushed line.
      // Glucose is exactly what that band is for, so it reads correctly here —
      // while HbA1c stays the headline number beside it.
      if (patient.spark.length >= 2) {
        children.add(Sparkline(values: patient.spark, color: color, width: 56, height: 22));
      }
      children.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text('HbA1c ', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
          Text('${hba1c.toStringAsFixed(1)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
          if (patient.hba1cAt != null)
            Text('  ·  ${_ago(patient.hba1cAt!)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ));
    } else {
      // No HbA1c yet — fall back to the recent glucose signal so nothing is lost.
      final trendColor = switch (patient.trend) {
        'up' => AppColors.warningOn(context),
        'down' => AppColors.successOn(context),
        _ => scheme.onSurfaceVariant,
      };
      final trendIcon = switch (patient.trend) {
        'up' => Icons.trending_up_rounded,
        'down' => Icons.trending_down_rounded,
        _ => Icons.trending_flat_rounded,
      };
      if (hasGlucoseSpark) {
        children.add(Sparkline(values: patient.spark, color: AppColors.accentOn(context), width: 60, height: 22));
      }
      if (patient.lastReadingValue != null) {
        children.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(trendIcon, size: 15, color: trendColor),
            const SizedBox(width: 3),
            Text('${patient.lastReadingValue!.round()}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            Text(' mg/dL', style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
            if (lastGlucose != null)
              Text('  ·  ${_ago(lastGlucose)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ));
      } else if (lastGlucose != null) {
        children.add(Text(_ago(lastGlucose), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)));
      }
    }
    if (overdue) {
      children.add(_Chip(
        label: 'Check-in due',
        fg: AppColors.warningOn(context),
        bg: AppColors.warningBgOn(context),
        icon: Icons.schedule_rounded,
      ));
    }

    // A Wrap so the sparkline + value + "due" chip flow onto a second line on a
    // narrow phone rather than clipping.
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: children),
    );
  }
}

/// Subtle inbox-preview icon for a media turn — a monochrome Material glyph, not
/// an emoji, so the row reads as premium.
IconData _mediaIcon(String type) {
  switch (type) {
    case 'voice':
      return Icons.mic_none_rounded;
    case 'photo':
      return Icons.photo_camera_rounded;
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'document':
      return Icons.description_rounded;
    default:
      return Icons.attach_file_rounded;
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

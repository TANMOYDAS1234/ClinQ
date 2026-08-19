import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../domain/medication.dart';
import 'medications_providers.dart';

/// The patient's medicine-taking history: every past scheduled dose over the
/// chosen window, marked taken / skipped / missed, grouped by day, so they can
/// see exactly what they took and when.
class DoseHistoryScreen extends ConsumerStatefulWidget {
  const DoseHistoryScreen({super.key});

  @override
  ConsumerState<DoseHistoryScreen> createState() => _DoseHistoryScreenState();
}

class _DoseHistoryScreenState extends ConsumerState<DoseHistoryScreen> {
  static const _periods = [(label: '7 days', days: 7), (label: '2 weeks', days: 14), (label: '30 days', days: 30)];
  int _days = 14;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(doseHistoryProvider(_days));

    return Scaffold(
      appBar: AppBar(title: const Text('Dose history')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: Row(
              children: [
                for (final p in _periods) ...[
                  _PeriodChip(label: p.label, selected: _days == p.days, onTap: () => setState(() => _days = p.days)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(doseHistoryProvider(_days)),
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text('Could not load your history', style: TextStyle(color: scheme.onSurfaceVariant))),
                ]),
                data: (doses) {
                  if (doses.isEmpty) {
                    return ListView(children: [
                      const SizedBox(height: 120),
                      Icon(Icons.medication_outlined, size: 52, color: scheme.outlineVariant),
                      const SizedBox(height: AppSpacing.md),
                      Center(child: Text('No doses in this period',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant))),
                    ]);
                  }
                  return _HistoryList(doses: doses);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.doses});
  final List<DoseHistoryEntry> doses;

  static String _dayLabel(DateTime at) {
    final now = DateTime.now();
    final d = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEEE, d MMM').format(at);
  }

  @override
  Widget build(BuildContext context) {
    // Group by calendar day (the backend already sorts newest-first).
    final byDay = <String, List<DoseHistoryEntry>>{};
    final order = <String>[];
    for (final dose in doses) {
      final at = dose.scheduledFor ?? DateTime.now();
      final key = DateFormat('yyyy-MM-dd').format(at);
      if (!byDay.containsKey(key)) {
        byDay[key] = [];
        order.add(key);
      }
      byDay[key]!.add(dose);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.xl),
      children: [
        for (final key in order) ...[
          Builder(builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            final list = byDay[key]!;
            final at = list.first.scheduledFor ?? DateTime.now();
            final taken = list.where((d) => d.status == 'taken').length;
            return Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
              child: Row(
                children: [
                  Text(_dayLabel(at), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('$taken/${list.length} taken', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            );
          }),
          for (final dose in byDay[key]!) _DoseRow(dose: dose),
        ],
      ],
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose});
  final DoseHistoryEntry dose;

  ({Color color, IconData icon, String label}) get _status => switch (dose.status) {
        'taken' => (color: AppColors.success, icon: Icons.check_circle_rounded, label: 'Taken'),
        'skipped' => (color: AppColors.warning, icon: Icons.remove_circle_rounded, label: 'Skipped'),
        _ => (color: AppColors.danger, icon: Icons.cancel_rounded, label: 'Missed'),
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _status;
    final time = dose.scheduledFor != null ? DateFormat('h:mm a').format(dose.scheduledFor!) : dose.time;
    final sub = [
      if (dose.strength != null && dose.strength!.isNotEmpty) dose.strength,
      time,
      if (dose.status == 'taken' && dose.takenAt != null) 'took ${DateFormat('h:mm a').format(dose.takenAt!)}',
    ].whereType<String>().join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(s.icon, color: s.color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(dose.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 0),
                Text(sub, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: s.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(s.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: s.color)),
          ),
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.primary : scheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? Colors.white : scheme.onSurface,
            )),
      ),
    );
  }
}

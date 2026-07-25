import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/providers/preferences_provider.dart';
import '../../../shared/services/notification_service.dart';
import '../../../shared/widgets/auto_refresh.dart';
import '../data/appointment_repository.dart';
import '../domain/clinic.dart';
import 'appointment_providers.dart';

/// Patient booking flow on one screen: choose clinic → choose date → choose an
/// available time → confirm. Slot availability auto-refreshes so a time taken
/// by someone else disappears while the patient is still deciding.
class BookAppointmentScreen extends ConsumerStatefulWidget {
  const BookAppointmentScreen({super.key});

  @override
  ConsumerState<BookAppointmentScreen> createState() => _BookAppointmentScreenState();
}

class _BookAppointmentScreenState extends ConsumerState<BookAppointmentScreen> {
  Clinic? _clinic;
  late DateTime _date;
  Slot? _slot;
  final _reason = TextEditingController();
  bool _booking = false;

  static const _daysAhead = 14;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_date);

  void _selectClinic(Clinic c) {
    setState(() {
      _clinic = c;
      _slot = null;
    });
  }

  void _selectDate(DateTime d) {
    setState(() {
      _date = d;
      _slot = null;
    });
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (_clinic == null || _slot == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.apptSelectSlotFirst)));
      return;
    }
    setState(() => _booking = true);
    try {
      await ref.read(appointmentRepositoryProvider).book(
        clinicId: _clinic!.id,
        scheduledForIso: _slot!.iso,
        reason: _reason.text.trim(),
      );
      ref.invalidate(myAppointmentsProvider);

      // Confirmation notification with short, specific copy.
      if (ref.read(appPreferencesProvider).appointmentAlerts) {
        final when = DateTime.tryParse(_slot!.iso)?.toLocal();
        final whenText = when != null ? DateFormat('EEE d MMM, h:mm a').format(when) : _slot!.time;
        NotificationService.instance.show(
          title: l10n.apptBookedTitle,
          body: '${_clinic!.name} · $whenText',
        );
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 40),
          title: Text(l10n.apptBookedTitle),
          content: Text(l10n.apptBookedBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.commonOk)),
          ],
        ),
      );
      navigator.pop();
    } on ApiException catch (e) {
      setState(() => _booking = false);
      final msg = e.code == 'BAD_REQUEST' ? l10n.apptSlotTaken : l10n.apptBookingFailed;
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      // The slot list may be stale — refresh it.
      if (_clinic != null) {
        ref.invalidate(slotDayProvider((clinicId: _clinic!.id, date: _dateKey)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final clinics = ref.watch(clinicsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.apptBook)),
      body: clinics.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => _ErrorRetry(onRetry: () => ref.invalidate(clinicsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(l10n.apptNoSlots, textAlign: TextAlign.center),
              ),
            );
          }
          // Default to the first clinic so the flow is one step shorter.
          _clinic ??= list.first;
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              120,
            ),
            children: [
              _SectionTitle(l10n.apptChooseClinic),
              ...list.map((c) => _ClinicOption(
                    clinic: c,
                    selected: c.id == _clinic?.id,
                    onTap: () => _selectClinic(c),
                  )),
              const SizedBox(height: AppSpacing.lg),
              _SectionTitle(l10n.apptChooseDate),
              _DateStrip(
                selected: _date,
                daysAhead: _daysAhead,
                onSelect: _selectDate,
              ),
              const SizedBox(height: AppSpacing.lg),
              _SectionTitle(l10n.apptChooseTime),
              AutoRefresh(
                onTick: (r) {
                  if (_clinic != null) {
                    r.invalidate(slotDayProvider((clinicId: _clinic!.id, date: _dateKey)));
                  }
                },
                child: _SlotGrid(
                  clinicId: _clinic!.id,
                  dateKey: _dateKey,
                  selected: _slot,
                  onSelect: (s) => setState(() => _slot = s),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _reason,
                maxLength: 300,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.apptReasonLabel,
                  hintText: l10n.apptReasonHint,
                ),
              ),
            ],
          );
        },
      ),
      bottomSheet: _clinic == null
          ? null
          : _ConfirmBar(
              enabled: _slot != null && !_booking,
              busy: _booking,
              slot: _slot,
              onConfirm: _confirm,
            ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _ClinicOption extends StatelessWidget {
  const _ClinicOption({required this.clinic, required this.selected, required this.onTap});

  final Clinic clinic;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.08) : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            border: Border.all(
              color: selected ? accent : scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.local_hospital_outlined, color: accent),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(clinic.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (clinic.locationLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        clinic.locationLine,
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: selected ? accent : scheme.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.daysAhead, required this.onSelect});

  final DateTime selected;
  final int daysAhead;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;
    final today = DateTime.now();

    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: daysAhead,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final d = DateTime(today.year, today.month, today.day + i);
          final isSel = d.year == selected.year && d.month == selected.month && d.day == selected.day;
          return InkWell(
            onTap: () => onSelect(d),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 56,
              decoration: BoxDecoration(
                color: isSel ? accent : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: isSel ? accent : scheme.outlineVariant.withValues(alpha: 0.6)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(d),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSel ? Colors.white : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: isSel ? Colors.white : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotGrid extends ConsumerWidget {
  const _SlotGrid({
    required this.clinicId,
    required this.dateKey,
    required this.selected,
    required this.onSelect,
  });

  final String clinicId;
  final String dateKey;
  final Slot? selected;
  final ValueChanged<Slot> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.primaryDark : AppColors.primary;
    final slotsAsync = ref.watch(slotDayProvider((clinicId: clinicId, date: dateKey)));

    return slotsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _ErrorRetry(
        onRetry: () => ref.invalidate(slotDayProvider((clinicId: clinicId, date: dateKey))),
      ),
      data: (day) {
        if (day.slots.isEmpty) {
          return _EmptyNote(icon: Icons.event_busy_outlined, text: l10n.apptClosedThatDay);
        }
        final anyAvailable = day.hasAvailability;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!anyAvailable) _EmptyNote(icon: Icons.schedule_outlined, text: l10n.apptNoSlots),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final s in day.slots)
                  _SlotChip(
                    slot: s,
                    selected: selected?.time == s.time,
                    accent: accent,
                    scheme: scheme,
                    onTap: s.available ? () => onSelect(s) : null,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.selected,
    required this.accent,
    required this.scheme,
    required this.onTap,
  });

  final Slot slot;
  final bool selected;
  final Color accent;
  final ColorScheme scheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent : (disabled ? scheme.surfaceContainerHighest.withValues(alpha: 0.5) : scheme.surface),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? accent : scheme.outlineVariant.withValues(alpha: disabled ? 0.4 : 0.8),
          ),
        ),
        child: Text(
          slot.time,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            decoration: disabled ? TextDecoration.lineThrough : null,
            color: selected
                ? Colors.white
                : (disabled ? scheme.onSurfaceVariant.withValues(alpha: 0.6) : scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.enabled, required this.busy, required this.slot, required this.onConfirm});

  final bool enabled;
  final bool busy;
  final Slot? slot;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
          onPressed: enabled ? onConfirm : null,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Text(
                  slot == null ? l10n.apptConfirmBooking : '${l10n.apptConfirmBooking} · ${slot!.time}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.commonSomethingWentWrong),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.commonRetry)),
        ],
      ),
    );
  }
}

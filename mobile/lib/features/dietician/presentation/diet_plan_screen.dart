import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../data/dietician_repository.dart';
import '../domain/diet_models.dart';
import 'dietician_providers.dart';

/// Where the dietician writes the patient's diet plan.
///
/// Chat guidance is easy to write and easy to lose — two hundred messages later
/// "so what do I eat at breakfast?" has no findable answer. This is the durable
/// form of the same advice: one document, edited in place, always current.
///
/// Saving and sending are separate buttons. A dietician halfway through moving
/// a portion from lunch to dinner should not be notifying the patient twice.
class DietPlanScreen extends ConsumerStatefulWidget {
  const DietPlanScreen({super.key, required this.patientId, this.patientName});

  final String patientId;
  final String? patientName;

  @override
  ConsumerState<DietPlanScreen> createState() => _DietPlanScreenState();
}

class _DietPlanScreenState extends ConsumerState<DietPlanScreen> {
  final _goal = TextEditingController();
  final _notes = TextEditingController();
  final _avoid = TextEditingController();

  List<_MealDraft> _meals = [];
  List<String> _avoidList = [];

  bool _loaded = false;
  bool _saving = false;
  bool _sending = false;
  bool _dirty = false;
  DateTime? _sharedAt;

  /// Offered when the plan is empty, so the first plan is a few taps rather than
  /// a blank page. Free text after that — an Indian day is not three meals.
  static const _suggestedMeals = ['Breakfast', 'Mid-morning', 'Lunch', 'Evening snack', 'Dinner'];

  /// Drives the enabled state of the "add" button beside the avoid field. It
  /// used to be always enabled and silently do nothing on an empty box, which
  /// reads as a broken button rather than as "type something first".
  bool _canAddAvoid = false;

  @override
  void initState() {
    super.initState();
    _avoid.addListener(() {
      final can = _avoid.text.trim().isNotEmpty;
      if (can != _canAddAvoid) setState(() => _canAddAvoid = can);
    });
    _load();
  }

  @override
  void dispose() {
    _goal.dispose();
    _notes.dispose();
    _avoid.dispose();
    for (final m in _meals) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final plan = await ref.read(dieticianRepositoryProvider).dietPlan(widget.patientId);
      if (!mounted) return;
      setState(() {
        _goal.text = plan?.goal ?? '';
        _notes.text = plan?.notes ?? '';
        _avoidList = List.of(plan?.avoid ?? const []);
        _meals = (plan?.meals ?? const []).map(_MealDraft.from).toList();
        _sharedAt = plan?.sharedAt;
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loaded = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  DietPlan get _current => DietPlan(
    goal: _goal.text.trim(),
    notes: _notes.text.trim(),
    avoid: _avoidList,
    meals: _meals.map((m) => m.toMeal()).where((m) => m.name.isNotEmpty).toList(),
  );

  Future<bool> _save({bool quiet = false}) async {
    setState(() => _saving = true);
    try {
      final saved = await ref.read(dieticianRepositoryProvider).saveDietPlan(widget.patientId, _current);
      ref.invalidate(dietPlanProvider(widget.patientId));
      ref.invalidate(dietDashboardProvider);
      if (!mounted) return true;
      setState(() {
        _saving = false;
        _dirty = false;
        _sharedAt = saved.sharedAt;
      });
      if (!quiet) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan saved')));
      }
      return true;
    } on ApiException catch (e) {
      if (!mounted) return false;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return false;
    }
  }

  Future<void> _send() async {
    // Send the version on screen, not the one last saved — otherwise an edit the
    // dietician can see would not be in the plan the patient receives.
    if (_dirty && !await _save(quiet: true)) return;

    setState(() => _sending = true);
    try {
      await ref.read(dieticianRepositoryProvider).sendDietPlan(widget.patientId);
      ref.invalidate(dietPlanProvider(widget.patientId));
      ref.invalidate(dietDashboardProvider);
      ref.invalidate(dietThreadProvider(widget.patientId));
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sharedAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent to the patient in their care thread')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _addMeal(String name) {
    setState(() {
      _meals.add(_MealDraft(name: name));
      _dirty = true;
    });
  }

  void _addAvoid() {
    final text = _avoid.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _avoidList = [..._avoidList, text];
      _avoid.clear();
      _dirty = true;
    });
  }

  /// Where the plan stands right now, in the order the dietician cares about:
  /// what is happening, then what is pending, then what is done.
  String get _statusText {
    if (_saving) return 'Saving…';
    if (_sending) return 'Sending…';
    if (_dirty) return 'Unsaved changes';
    if (_sharedAt == null) return 'Saved · not sent to the patient yet';
    return 'Saved · sent ${DateFormat('d MMM, h:mm a').format(_sharedAt!)}';
  }

  IconData get _statusIcon {
    if (_saving || _sending) return Icons.sync_rounded;
    if (_dirty) return Icons.edit_note_rounded;
    if (_sharedAt == null) return Icons.check_circle_outline_rounded;
    return Icons.check_circle_rounded;
  }

  Color _statusColour(ColorScheme scheme) {
    if (_dirty) return AppColors.warning;
    if (_sharedAt != null && !_saving && !_sending) return AppColors.primary;
    return scheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _current;
    final canSend = plan.meals.isNotEmpty || plan.goal.isNotEmpty || plan.avoid.isNotEmpty;

    return PopScope(
      // Keeps an unsent draft. Without a Save button, walking back from a
      // half-written plan would otherwise throw the work away — and a diet plan
      // is twenty minutes of typing, not a form.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final navigator = Navigator.of(context);
        await _save(quiet: true);
        if (mounted) navigator.pop();
      },
      child: _body(context, scheme, canSend),
    );
  }

  Widget _body(BuildContext context, ColorScheme scheme, bool canSend) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Plan Editor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (widget.patientName != null)
              Text(
                'for ${widget.patientName!}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          // No Save button: "Send to patient" below already saves first, and two
          // commit actions on one form invites sending a plan that was meant to
          // stay a draft. Unsent edits are kept by the auto-save on leaving.
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
              children: [
                _Label('Primary clinical goal'),
                TextField(
                  controller: _goal,
                  minLines: 2,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _dirty = true,
                  style: const TextStyle(fontSize: 15.5, height: 1.45),
                  decoration: InputDecoration(
                    hintText: 'e.g. Bring fasting sugar under 130 without cutting rice completely',
                    filled: true,
                    fillColor: scheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.all(16),
                    border: _softBorder(scheme),
                    enabledBorder: _softBorder(scheme),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.accentOn(context), width: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                _Label('Structured meals'),
                for (var i = 0; i < _meals.length; i++)
                  _MealCard(
                    draft: _meals[i],
                    onChanged: () => setState(() => _dirty = true),
                    onRemove: () => setState(() {
                      _meals.removeAt(i).dispose();
                      _dirty = true;
                    }),
                  ),
                // The add area, marked out as one block. A single "Add meal"
                // button would have made the dietician name every meal from
                // scratch; the named chips are the same affordance with the
                // usual answer already filled in.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    border: Border.all(
                      color: AppColors.accentOn(context).withValues(alpha: 0.35),
                    ),
                    color: AppColors.accentOn(context).withValues(alpha: 0.04),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADD MEAL / SNACK',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                          color: AppColors.accentOn(context),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final name in [..._suggestedMeals, ''])
                      if (name.isEmpty ||
                          !_meals.any(
                            (m) => m.name.text.trim().toLowerCase() == name.toLowerCase(),
                          ))
                        ActionChip(
                          avatar: Icon(Icons.add_rounded, size: 18, color: AppColors.accentOn(context)),
                          label: Text(
                            name.isEmpty ? 'Other' : name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          labelPadding: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          backgroundColor: scheme.surfaceContainerLowest,
                          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onPressed: () => _addMeal(name),
                        ),
                  ],
                ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Kept out of the meal cards on purpose: a patient scanning for
                // "can I have this?" should have one place to look. Given its
                // own card with a red edge, because it is the only part of a
                // plan that is a prohibition rather than a suggestion.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                    border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                    // A rule across the top rather than a full red border: the
                    // section is a caution, not an alarm.
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B1B33).withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 19, color: AppColors.dangerOn(context)),
                          const SizedBox(width: 8),
                          Text(
                            'Best Avoided',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.dangerOn(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_avoidList.isNotEmpty) ...[
                        Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _avoidList.length; i++)
                        Chip(
                          label: Text(
                            _avoidList[i],
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: AppColors.dangerBgOn(context),
                          side: BorderSide(color: AppColors.dangerOn(context).withValues(alpha: 0.28)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          deleteIconColor: AppColors.danger,
                          onDeleted: () => setState(() {
                            _avoidList = [..._avoidList]..removeAt(i);
                            _dirty = true;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _avoid,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _addAvoid(),
                        decoration: InputDecoration(
                          hintText: 'e.g. Sweetened lassi',
                          filled: true,
                          fillColor: scheme.surfaceContainerLowest,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          border: _softBorder(scheme),
                          enabledBorder: _softBorder(scheme),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(color: AppColors.accentOn(context), width: 1.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    // Disabled until there is something to add, so an empty tap
                    // no longer looks like a dead button.
                    SizedBox(
                      height: 52,
                      width: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: scheme.surfaceContainerHighest,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _canAddAvoid ? _addAvoid : null,
                        child: const Icon(Icons.add_rounded, size: 24),
                      ),
                    ),
                  ],
                ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                _Label('Anything else'),
                TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _dirty = true,
                  style: const TextStyle(fontSize: 15.5, height: 1.45),
                  decoration: InputDecoration(
                    hintText: 'Water, cooking oil, eating out, fasting days…',
                    filled: true,
                    fillColor: scheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.all(16),
                    border: _softBorder(scheme),
                    enabledBorder: _softBorder(scheme),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.accentOn(context), width: 1.4),
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: !_loaded
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Says where the plan stands at all times. With no Save
                  // button there was nothing on screen to confirm the work had
                  // been stored, which reads exactly like it has not been.
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_statusIcon, size: 14, color: _statusColour(scheme)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _statusText,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _statusColour(scheme),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: AppSpacing.minTapTarget + 6,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      onPressed: (!canSend || _sending || _saving) ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, size: 20),
                      label: Text(
                        _sharedAt == null ? 'Send to patient' : 'Send the updated plan',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// The resting outline shared by every field on this screen. A hairline rather
/// than Material's default underline: the form is long, and a dozen heavy
/// underlines read as clutter where a card edge reads as structure.
OutlineInputBorder _softBorder(ColorScheme scheme) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(14),
  borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
);

/// A meal being edited. Items are one controller per line so a dietician can
/// fix "2 rotis" without retyping the rest of the meal.
class _MealDraft {
  _MealDraft({String name = '', String time = '', List<String> items = const [], String notes = ''})
    : name = TextEditingController(text: name),
      time = TextEditingController(text: time),
      notes = TextEditingController(text: notes),
      items = items.map((i) => TextEditingController(text: i)).toList();

  factory _MealDraft.from(DietMeal m) =>
      _MealDraft(name: m.name, time: m.time, items: m.items, notes: m.notes);

  final TextEditingController name;
  final TextEditingController time;
  final TextEditingController notes;
  List<TextEditingController> items;

  DietMeal toMeal() => DietMeal(
    name: name.text.trim(),
    time: time.text.trim(),
    items: items.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList(),
    notes: notes.text.trim(),
  );

  void dispose() {
    name.dispose();
    time.dispose();
    notes.dispose();
    for (final c in items) {
      c.dispose();
    }
  }
}

class _MealCard extends StatefulWidget {
  const _MealCard({required this.draft, required this.onChanged, required this.onRemove});

  final _MealDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  State<_MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<_MealCard> {
  /// Reads the stored string back into a [TimeOfDay] so the picker opens on the
  /// time already set rather than on the current hour. Accepts both the
  /// 12-hour form this screen writes and a bare 24-hour "HH:mm", because plans
  /// saved before the picker existed were typed by hand.
  TimeOfDay? get _parsedTime {
    final raw = widget.draft.time.text.trim().toLowerCase();
    if (raw.isEmpty) return null;
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})\s*(am|pm)?$').firstMatch(raw);
    if (m == null) return null;
    var hour = int.tryParse(m.group(1)!) ?? 0;
    final minute = int.tryParse(m.group(2)!) ?? 0;
    final suffix = m.group(3);
    if (suffix == 'pm' && hour < 12) hour += 12;
    if (suffix == 'am' && hour == 12) hour = 0;
    if (hour > 23 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _parsedTime ?? const TimeOfDay(hour: 8, minute: 0),
      helpText: 'When should this meal be?',
    );
    if (picked == null || !mounted) return;
    setState(() {
      widget.draft.time.text = picked.format(context);
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = widget.draft;
    final time = d.time.text.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A rail down the edge, so a column of meals reads as a sequence of
            // blocks rather than as one long form.
            Container(width: 4, color: AppColors.accentOn(context)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
                child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Sun or moon by the hour it falls, so the list can be scanned by
              // time of day without reading the names.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  (_parsedTime?.hour ?? 8) >= 17 ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                  size: 18,
                  color: AppColors.accentOn(context),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: d.name,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => widget.onChanged(),
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  decoration: const InputDecoration(
                    hintText: 'Meal name',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove this meal',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemove,
                icon: Icon(Icons.close_rounded, size: 20, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // A picker, not a text box. Typing the time by hand produced "8",
          // "8pm", "20:00" and "8 o'clock" in the same plan, and the patient's
          // side has to render whatever was typed.
          Align(
            alignment: Alignment.centerLeft,
            child: Material(
              color: time.isEmpty ? scheme.surfaceContainerHigh : AppColors.accentSoftOn(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickTime,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule_rounded,
                        size: 18,
                        color: time.isEmpty ? scheme.onSurfaceVariant : AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time.isEmpty ? 'Set a time' : time,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: time.isEmpty ? scheme.onSurfaceVariant : AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md, bottom: 4, right: AppSpacing.sm),
            child: Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
          ),

          for (var i = 0; i < d.items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: AppColors.accentOn(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: d.items[i],
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => widget.onChanged(),
                      style: const TextStyle(fontSize: 15.5),
                      decoration: const InputDecoration(
                        hintText: 'e.g. 2 rotis, no ghee',
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove this item',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      d.items.removeAt(i).dispose();
                      widget.onChanged();
                    }),
                    icon: Icon(
                      Icons.remove_circle_outline_rounded,
                      size: 19,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onPressed: () => setState(() {
                d.items = [...d.items, TextEditingController()];
                widget.onChanged();
              }),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text(
                'Add item',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: TextField(
              controller: d.notes,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => widget.onChanged(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Note for this meal (optional)',
                filled: true,
                fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.45),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.accentOn(context), width: 1.4),
                ),
              ),
            ),
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.sm),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plan = _current;
    final canSend = plan.meals.isNotEmpty || plan.goal.isNotEmpty || plan.avoid.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Diet plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (widget.patientName != null)
              Text(
                widget.patientName!,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, 120),
              children: [
                _Label('Goal'),
                TextField(
                  controller: _goal,
                  minLines: 2,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _dirty = true,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Bring fasting sugar under 130 without cutting rice completely',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                _Label('Meals'),
                for (var i = 0; i < _meals.length; i++)
                  _MealCard(
                    draft: _meals[i],
                    onChanged: () => setState(() => _dirty = true),
                    onRemove: () => setState(() {
                      _meals.removeAt(i).dispose();
                      _dirty = true;
                    }),
                  ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final name in _suggestedMeals)
                      if (!_meals.any((m) => m.name.text.trim().toLowerCase() == name.toLowerCase()))
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 17),
                          label: Text(name),
                          onPressed: () => _addMeal(name),
                        ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Other'),
                      onPressed: () => _addMeal(''),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // Kept out of the meal cards on purpose: a patient scanning for
                // "can I have this?" should have one place to look.
                _Label('Best avoided'),
                if (_avoidList.isNotEmpty)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var i = 0; i < _avoidList.length; i++)
                        Chip(
                          label: Text(_avoidList[i]),
                          onDeleted: () => setState(() {
                            _avoidList = [..._avoidList]..removeAt(i);
                            _dirty = true;
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _avoid,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addAvoid(),
                        decoration: const InputDecoration(hintText: 'Add a food to avoid'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    IconButton.filledTonal(onPressed: _addAvoid, icon: const Icon(Icons.add_rounded)),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                _Label('Anything else'),
                TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => _dirty = true,
                  decoration: const InputDecoration(
                    hintText: 'Water, cooking oil, eating out, fasting days…',
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
                  if (_sharedAt == null && canSend)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        'The patient has not been sent this plan yet.',
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
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
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = widget.draft;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: d.name,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => widget.onChanged(),
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    hintText: 'Meal name',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: d.time,
                  textAlign: TextAlign.end,
                  onChanged: (_) => widget.onChanged(),
                  style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  decoration: const InputDecoration(
                    hintText: '8:00 am',
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemove,
                icon: Icon(Icons.close_rounded, size: 19, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const Divider(height: AppSpacing.md),
          for (var i = 0; i < d.items.length; i++)
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Text('•', style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant)),
                ),
                Expanded(
                  child: TextField(
                    controller: d.items[i],
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => widget.onChanged(),
                    decoration: const InputDecoration(
                      hintText: 'e.g. 2 rotis, no ghee',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    d.items.removeAt(i).dispose();
                    widget.onChanged();
                  }),
                  icon: Icon(Icons.remove_circle_outline_rounded, size: 18, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(() {
                d.items = [...d.items, TextEditingController()];
                widget.onChanged();
              }),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add item'),
            ),
          ),
          TextField(
            controller: d.notes,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => widget.onChanged(),
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            decoration: const InputDecoration(
              hintText: 'Note for this meal (optional)',
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
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
